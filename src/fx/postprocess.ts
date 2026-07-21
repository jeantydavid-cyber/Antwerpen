import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/examples/jsm/postprocessing/ShaderPass.js';
import type { PostFX } from '../types';
import { PALETTE } from '../palette';
import { clamp } from '../lib/utils';

const BLOOM_STRENGTH = 0.42;
const BLOOM_RADIUS = 0.45;
const BLOOM_THRESHOLD = 0.72;

const BASE_VIGNETTE_STRENGTH = 0.62;
const MAX_VIGNETTE_BOOST = 0.18;
const BASE_GRAIN_STRENGTH = 0.045;
const MAX_GRAIN_BOOST = 0.03;
const BASE_DESATURATION = 0.35;

const gradeShader = {
  uniforms: {
    tDiffuse: { value: null },
    uTime: { value: 0 },
    uVignetteStrength: { value: BASE_VIGNETTE_STRENGTH },
    uGrainStrength: { value: BASE_GRAIN_STRENGTH },
    uDesaturation: { value: BASE_DESATURATION },
    uWarmColor: { value: new THREE.Color(PALETTE.candleAmber) },
    uEmberColor: { value: new THREE.Color(PALETTE.pomegranateRed) },
  },
  vertexShader: /* glsl */ `
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }
  `,
  fragmentShader: /* glsl */ `
    uniform sampler2D tDiffuse;
    uniform float uTime;
    uniform float uVignetteStrength;
    uniform float uGrainStrength;
    uniform float uDesaturation;
    uniform vec3 uWarmColor;
    uniform vec3 uEmberColor;
    varying vec2 vUv;

    float grainHash(vec2 p) {
      return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
    }

    void main() {
      vec4 srcColor = texture2D(tDiffuse, vUv);
      vec3 color = srcColor.rgb;

      float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
      vec3 grey = vec3(luma);

      float warmAffinity = max(
        1.0 - distance(normalize(color + 1e-5), normalize(uWarmColor)),
        1.0 - distance(normalize(color + 1e-5), normalize(uEmberColor))
      );
      warmAffinity = clamp(warmAffinity, 0.0, 1.0);
      warmAffinity = smoothstep(0.55, 0.95, warmAffinity) * clamp(luma * 1.6, 0.0, 1.0);

      float desat = uDesaturation * (1.0 - warmAffinity);
      color = mix(color, grey, desat);

      vec2 centered = vUv - 0.5;
      float vignetteDist = length(centered * vec2(1.0, 0.86));
      float vignette = smoothstep(0.32, uVignetteStrength + 0.32, vignetteDist);
      color *= 1.0 - vignette * 0.85;

      float grain = grainHash(vUv * vec2(1920.0, 1080.0) + uTime) - 0.5;
      color += grain * uGrainStrength;

      gl_FragColor = vec4(clamp(color, 0.0, 1.0), srcColor.a);
    }
  `,
};

export function createPostFX(
  renderer: THREE.WebGLRenderer,
  scene: THREE.Scene,
  camera: THREE.PerspectiveCamera,
): PostFX {
  const size = new THREE.Vector2();
  renderer.getSize(size);

  const composer = new EffectComposer(renderer);
  composer.setSize(size.x, size.y);

  const renderPass = new RenderPass(scene, camera);
  composer.addPass(renderPass);

  const bloomPass = new UnrealBloomPass(size.clone(), BLOOM_STRENGTH, BLOOM_RADIUS, BLOOM_THRESHOLD);
  composer.addPass(bloomPass);

  const gradePass = new ShaderPass(gradeShader);
  gradePass.renderToScreen = true;
  composer.addPass(gradePass);

  let elapsed = 0;
  let reducedMotion = false;
  let gradeIntensity = 0;

  return {
    render() {
      if (!reducedMotion) elapsed += 1 / 60;
      gradePass.uniforms.uTime.value = elapsed;
      gradePass.uniforms.uVignetteStrength.value = BASE_VIGNETTE_STRENGTH + gradeIntensity * MAX_VIGNETTE_BOOST;
      gradePass.uniforms.uGrainStrength.value = reducedMotion
        ? 0
        : BASE_GRAIN_STRENGTH + gradeIntensity * MAX_GRAIN_BOOST;
      composer.render();
    },

    setSize(w: number, h: number) {
      composer.setSize(w, h);
      bloomPass.setSize(w, h);
    },

    setReducedMotion(reduced: boolean) {
      reducedMotion = reduced;
    },

    setGradeIntensity(level: number) {
      gradeIntensity = clamp(level, 0, 1);
    },
  };
}
