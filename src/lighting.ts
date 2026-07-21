import * as THREE from 'three';
import type { LightingSystem } from './types';
import { PALETTE } from './palette';
import { clamp, lerp, smoothstep } from './lib/utils';
import { fractalNoise1D } from './lib/noise';

const CANDLE_BASE_INTENSITY = 13;
const CANDLE_RANGE = 11;
const SHADOW_MAP_SIZE = 512;
const MIN_INTENSITY_FLOOR = 0.05;

const FLICKER_MIN_AMPLITUDE = 0.1;
const FLICKER_MAX_AMPLITUDE = 0.62;
const FLICKER_MIN_SPEED = 0.5;
const FLICKER_MAX_SPEED = 3.8;

const MIN_JITTER = 0.0015;
const MAX_JITTER = 0.014;

const TENSION_SMOOTH_RATE = 2.5;

const STEADY_AMPLITUDE = 0.08;
const STEADY_DURATION = 2.4;

const GUTTER_AMPLITUDE = 0.06;
const GUTTER_MIN_BASE_SCALE = 0.05;
const GUTTER_DIP_DURATION = 1.3;
const GUTTER_RECOVER_DURATION = 3.4;

const MOON_INTENSITY = 3.2;

const WINDOW_ANCHOR = new THREE.Vector3(0.9, 2.35, -3.6);
const WINDOW_TARGET = new THREE.Vector3(0.5, 0, -1.1);
const MOONBEAM_INTENSITY = 45;

const REDUCED_MOTION_AMPLITUDE_SCALE = 0.35;
const REDUCED_MOTION_JITTER_SCALE = 0.15;
const REDUCED_MOTION_LERP_RATE = 3;

function createFlameGlowTexture(): THREE.CanvasTexture {
  const size = 64;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d')!;
  const gradient = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  gradient.addColorStop(0, 'rgba(255,255,255,1)');
  gradient.addColorStop(0.35, 'rgba(244,200,120,0.85)');
  gradient.addColorStop(1, 'rgba(233,168,76,0)');
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, size, size);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

type ResolveMode = 'none' | 'steady' | 'gutter';

export function createLightingSystem(scene: THREE.Scene, candleAnchor: THREE.Object3D): LightingSystem {
  const candleLight = new THREE.PointLight(PALETTE.candleAmber, CANDLE_BASE_INTENSITY, CANDLE_RANGE, 2);
  candleLight.castShadow = true;
  candleLight.shadow.mapSize.set(SHADOW_MAP_SIZE, SHADOW_MAP_SIZE);
  candleLight.shadow.camera.near = 0.05;
  candleLight.shadow.camera.far = CANDLE_RANGE;
  candleLight.shadow.bias = -0.0025;
  scene.add(candleLight);

  const moonLight = new THREE.HemisphereLight(PALETTE.coalBlueGrey, PALETTE.coalBlack, MOON_INTENSITY);
  scene.add(moonLight);

  const moonBeam = new THREE.SpotLight(PALETTE.dirtySnow, MOONBEAM_INTENSITY, 12, Math.PI / 4.2, 0.7, 1.2);
  moonBeam.position.copy(WINDOW_ANCHOR);
  moonBeam.target.position.copy(WINDOW_TARGET);
  scene.add(moonBeam);
  scene.add(moonBeam.target);

  const flameTexture = createFlameGlowTexture();
  const flameMaterial = new THREE.SpriteMaterial({
    map: flameTexture,
    color: new THREE.Color(PALETTE.candleHighlight),
    blending: THREE.AdditiveBlending,
    transparent: true,
    depthWrite: false,
    fog: false,
  });
  const flameSprite = new THREE.Sprite(flameMaterial);
  flameSprite.scale.setScalar(0.13);
  scene.add(flameSprite);

  const colorLow = new THREE.Color(PALETTE.candleAmber);
  const colorHigh = new THREE.Color(PALETTE.candleHighlight);
  const tmpPosition = new THREE.Vector3();

  let targetTension = 0.05;
  let currentTension = 0.05;

  let resolveMode: ResolveMode = 'none';
  let resolveTimer = 0;
  let resolveStartAmplitude = FLICKER_MIN_AMPLITUDE;

  let reducedMotionTarget = 0;
  let reducedMotionFactor = 0;

  function amplitudeEnvelope(): number {
    const tensionEase = currentTension * currentTension;
    if (resolveMode === 'none') {
      return lerp(FLICKER_MIN_AMPLITUDE, FLICKER_MAX_AMPLITUDE, tensionEase);
    }
    if (resolveMode === 'steady') {
      const t = smoothstep(0, STEADY_DURATION, resolveTimer);
      return lerp(resolveStartAmplitude, STEADY_AMPLITUDE, t);
    }
    if (resolveTimer <= GUTTER_DIP_DURATION) {
      const t = smoothstep(0, GUTTER_DIP_DURATION, resolveTimer);
      return lerp(resolveStartAmplitude, GUTTER_AMPLITUDE, t);
    }
    const t = smoothstep(GUTTER_DIP_DURATION, GUTTER_DIP_DURATION + GUTTER_RECOVER_DURATION, resolveTimer);
    return lerp(GUTTER_AMPLITUDE, STEADY_AMPLITUDE, t);
  }

  function baseScaleEnvelope(): number {
    if (resolveMode !== 'gutter') return 1;
    if (resolveTimer <= GUTTER_DIP_DURATION) {
      const t = smoothstep(0, GUTTER_DIP_DURATION, resolveTimer);
      return lerp(1, GUTTER_MIN_BASE_SCALE, t);
    }
    const t = smoothstep(GUTTER_DIP_DURATION, GUTTER_DIP_DURATION + GUTTER_RECOVER_DURATION, resolveTimer);
    return lerp(GUTTER_MIN_BASE_SCALE, 1, t);
  }

  return {
    candleLight,
    moonLight,

    setTensionLevel(level: number) {
      targetTension = clamp(level, 0, 1);
    },

    setReducedMotion(reduced: boolean) {
      reducedMotionTarget = reduced ? 1 : 0;
    },

    resolveSteady() {
      resolveStartAmplitude = amplitudeEnvelope();
      resolveMode = 'steady';
      resolveTimer = 0;
    },

    resolveGutterAndRecover() {
      resolveStartAmplitude = amplitudeEnvelope();
      resolveMode = 'gutter';
      resolveTimer = 0;
    },

    update(dt: number, elapsed: number) {
      currentTension = lerp(currentTension, targetTension, clamp(dt * TENSION_SMOOTH_RATE, 0, 1));
      reducedMotionFactor = lerp(reducedMotionFactor, reducedMotionTarget, clamp(dt * REDUCED_MOTION_LERP_RATE, 0, 1));
      if (resolveMode !== 'none') resolveTimer += dt;

      const tensionEase = currentTension * currentTension;
      const amplitude = amplitudeEnvelope() * lerp(1, REDUCED_MOTION_AMPLITUDE_SCALE, reducedMotionFactor);
      const baseScale = baseScaleEnvelope();
      const speed = lerp(FLICKER_MIN_SPEED, FLICKER_MAX_SPEED, tensionEase);

      const flickerN = fractalNoise1D(elapsed * speed, 4) * 2 - 1;
      const colorN = fractalNoise1D(elapsed * speed * 1.7 + 41.2, 3);
      const jitterX = fractalNoise1D(elapsed * speed * 0.55 + 91.7, 3) * 2 - 1;
      const jitterY = fractalNoise1D(elapsed * speed * 0.55 + 173.3, 3) * 2 - 1;
      const jitterZ = fractalNoise1D(elapsed * speed * 0.55 + 257.9, 3) * 2 - 1;

      const flickerFactor = 1 + flickerN * amplitude;
      const intensity = Math.max(MIN_INTENSITY_FLOOR, CANDLE_BASE_INTENSITY * baseScale * flickerFactor);
      candleLight.intensity = intensity;

      candleLight.color.copy(colorLow);
      candleLight.color.lerp(colorHigh, clamp(colorN + amplitude * 0.3, 0, 1));

      candleAnchor.getWorldPosition(tmpPosition);
      const jitterScale = lerp(MIN_JITTER, MAX_JITTER, tensionEase) * baseScale * lerp(1, REDUCED_MOTION_JITTER_SCALE, reducedMotionFactor);
      tmpPosition.x += jitterX * jitterScale;
      tmpPosition.y += jitterY * jitterScale * 0.4;
      tmpPosition.z += jitterZ * jitterScale * 0.6;
      candleLight.position.copy(tmpPosition);

      flameSprite.position.copy(tmpPosition);
      flameSprite.scale.setScalar(0.11 + 0.045 * flickerFactor * baseScale);
      flameMaterial.opacity = clamp(intensity / CANDLE_BASE_INTENSITY, 0.08, 1);
    },
  };
}
