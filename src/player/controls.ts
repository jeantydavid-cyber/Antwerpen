import * as THREE from 'three';
import { PointerLockControls } from 'three/examples/jsm/controls/PointerLockControls.js';
import type { Controls, InteractableDef } from '../types';
import { clamp, lerp, smoothstep } from '../lib/utils';

const WALK_SPEED = 2.15;
const ACCEL_RATE = 7;
const DECEL_RATE = 10;

const PLAYER_RADIUS = 0.3;

const STAND_EYE_HEIGHT = 1.65;
const CROUCH_EYE_HEIGHT = 1.1;
const CROUCH_LERP_RATE = 6;

const INTERACTION_REACH = 2.2;

const BOB_CYCLES_PER_SECOND_AT_WALK = 1.8;
const BOB_VERTICAL_AMPLITUDE = 0.028;
const BOB_LATERAL_AMPLITUDE = 0.016;
const BOB_INTENSITY_RAMP = 0.2 * WALK_SPEED;

const BREATH_ANGULAR_SPEED = (Math.PI * 2) / 4.2;
const BREATH_VERTICAL_AMPLITUDE = 0.009;
const BREATH_LATERAL_AMPLITUDE = 0.005;

const MOTION_FACTOR_LERP_RATE = 3.5;

type Collider = { minX: number; maxX: number; minZ: number; maxZ: number };

export function createControls(
  camera: THREE.PerspectiveCamera,
  domElement: HTMLElement,
  colliders: Collider[],
): Controls {
  const plc = new PointerLockControls(camera, domElement);
  const doc = domElement.ownerDocument;

  const lockChangeListeners: Array<(locked: boolean) => void> = [];
  doc.addEventListener('pointerlockchange', () => {
    const locked = doc.pointerLockElement === domElement;
    for (const cb of lockChangeListeners) cb(locked);
  });
  doc.addEventListener('pointerlockerror', () => {
    for (const cb of lockChangeListeners) cb(false);
  });

  const keys = { forward: false, back: false, left: false, right: false, shift: false };
  window.addEventListener('keydown', (e) => setKeyState(e.code, true));
  window.addEventListener('keyup', (e) => setKeyState(e.code, false));

  function setKeyState(code: string, down: boolean) {
    if (code === 'KeyW') keys.forward = down;
    else if (code === 'KeyS') keys.back = down;
    else if (code === 'KeyA') keys.left = down;
    else if (code === 'KeyD') keys.right = down;
    else if (code === 'ShiftLeft' || code === 'ShiftRight') keys.shift = down;
  }

  let externalCrouch = false;
  let crouchT = 0;

  let reducedMotion = false;
  let motionFactor = 1;

  let groundPosition: THREE.Vector2 | null = null;
  const velocity = new THREE.Vector2();
  let bobPhase = 0;
  let elapsed = 0;

  // Eye height is applied on top of a floor reference captured from wherever
  // the caller placed the camera before the first update() — this lets the
  // caller set spawn position/rotation on yawObject without knowing about
  // crouch/bob internals.
  let floorY: number | null = null;

  const forwardDir = new THREE.Vector3();
  const rightDir = new THREE.Vector3();
  const raycaster = new THREE.Raycaster();
  raycaster.far = INTERACTION_REACH;
  const NDC_CENTER = new THREE.Vector2(0, 0);

  function resolveAxis(current: number, delta: number, otherAxisValue: number, axis: 'x' | 'z'): number {
    if (delta === 0) return current;
    const next = current + delta;
    for (const c of colliders) {
      const blockedOnThisAxis =
        axis === 'x'
          ? next + PLAYER_RADIUS > c.minX && next - PLAYER_RADIUS < c.maxX
          : next + PLAYER_RADIUS > c.minZ && next - PLAYER_RADIUS < c.maxZ;
      const overlapsOtherAxis =
        axis === 'x'
          ? otherAxisValue + PLAYER_RADIUS > c.minZ && otherAxisValue - PLAYER_RADIUS < c.maxZ
          : otherAxisValue + PLAYER_RADIUS > c.minX && otherAxisValue - PLAYER_RADIUS < c.maxX;
      if (blockedOnThisAxis && overlapsOtherAxis) return current;
    }
    return next;
  }

  function updateFacingVectors() {
    camera.getWorldDirection(forwardDir);
    forwardDir.y = 0;
    if (forwardDir.lengthSq() < 1e-8) forwardDir.set(0, 0, -1);
    forwardDir.normalize();
    rightDir.crossVectors(forwardDir, camera.up).normalize();
  }

  return {
    yawObject: plc.getObject(),

    isLocked: () => plc.isLocked,
    lock: () => plc.lock(),
    unlock: () => plc.unlock(),
    onLockChange(cb) {
      lockChangeListeners.push(cb);
    },

    setCrouch(crouching: boolean) {
      externalCrouch = crouching;
    },

    setReducedMotion(reduced: boolean) {
      reducedMotion = reduced;
    },

    update(dt: number) {
      if (floorY === null) floorY = camera.position.y - STAND_EYE_HEIGHT;
      if (groundPosition === null) groundPosition = new THREE.Vector2(camera.position.x, camera.position.z);
      elapsed += dt;

      updateFacingVectors();

      const inputActive = plc.isLocked;
      const inForward = inputActive ? Number(keys.forward) - Number(keys.back) : 0;
      const inRight = inputActive ? Number(keys.right) - Number(keys.left) : 0;

      const target = new THREE.Vector2(
        forwardDir.x * inForward + rightDir.x * inRight,
        forwardDir.z * inForward + rightDir.z * inRight,
      );
      if (target.lengthSq() > 1) target.normalize();
      target.multiplyScalar(WALK_SPEED);

      const accelerating = target.lengthSq() > velocity.lengthSq();
      const rate = accelerating ? ACCEL_RATE : DECEL_RATE;
      velocity.lerp(target, clamp(dt * rate, 0, 1));

      const deltaX = velocity.x * dt;
      const deltaZ = velocity.y * dt;
      const nextX = resolveAxis(groundPosition.x, deltaX, groundPosition.y, 'x');
      const nextZ = resolveAxis(groundPosition.y, deltaZ, nextX, 'z');
      groundPosition.set(nextX, nextZ);

      const crouchTarget = externalCrouch || keys.shift ? 1 : 0;
      crouchT = lerp(crouchT, crouchTarget, clamp(dt * CROUCH_LERP_RATE, 0, 1));
      const eyeHeight = lerp(STAND_EYE_HEIGHT, CROUCH_EYE_HEIGHT, crouchT);

      motionFactor = lerp(motionFactor, reducedMotion ? 0 : 1, clamp(dt * MOTION_FACTOR_LERP_RATE, 0, 1));

      const speed = velocity.length();
      const movementIntensity = smoothstep(0, BOB_INTENSITY_RAMP, speed);
      bobPhase += speed * dt * BOB_CYCLES_PER_SECOND_AT_WALK * Math.PI * 2;
      const bobVertical = Math.sin(bobPhase * 2) * BOB_VERTICAL_AMPLITUDE * movementIntensity * motionFactor;
      const bobLateral = Math.sin(bobPhase) * BOB_LATERAL_AMPLITUDE * movementIntensity * motionFactor;

      const breathPhase = elapsed * BREATH_ANGULAR_SPEED;
      const breathVertical = Math.sin(breathPhase) * BREATH_VERTICAL_AMPLITUDE * motionFactor;
      const breathLateral = Math.sin(breathPhase * 0.5 + 1.3) * BREATH_LATERAL_AMPLITUDE * motionFactor;

      const lateralOffset = bobLateral + breathLateral;
      camera.position.x = groundPosition.x + rightDir.x * lateralOffset;
      camera.position.z = groundPosition.y + rightDir.z * lateralOffset;
      camera.position.y = floorY + eyeHeight + bobVertical + breathVertical;
    },

    getInteractionTarget(interactables: InteractableDef[]): InteractableDef | null {
      raycaster.setFromCamera(NDC_CENTER, camera);
      let closest: InteractableDef | null = null;
      let closestDistance = Infinity;
      for (const def of interactables) {
        const hits = raycaster.intersectObject(def.object, true);
        if (hits.length === 0) continue;
        const hit = hits[0];
        if (hit.distance <= INTERACTION_REACH && hit.distance < closestDistance) {
          closestDistance = hit.distance;
          closest = def;
        }
      }
      return closest;
    },
  };
}
