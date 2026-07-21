import * as THREE from 'three';
import { createRoomScene } from './scene/room';
import { createLightingSystem } from './lighting';
import { createPostFX } from './fx/postprocess';
import { createControls } from './player/controls';
import { createSoundscape } from './audio/soundscape';
import { createStorySequencer } from './sequence/story';
import { createUIPrompts } from './ui/prompts';
import type { EndingId, StoryBeat } from './types';

const canvas = document.getElementById('scene') as HTMLCanvasElement;

const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.6;

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(68, window.innerWidth / window.innerHeight, 0.05, 50);

const room = createRoomScene();
scene.add(room.group);

const lighting = createLightingSystem(scene, room.candleFlameAnchor);
const postfx = createPostFX(renderer, scene, camera);
const controls = createControls(camera, renderer.domElement, room.colliders);
const soundscape = createSoundscape(camera, scene);
const story = createStorySequencer(room);
const ui = createUIPrompts();

scene.add(controls.yawObject);
controls.yawObject.position.copy(room.playerSpawn);
controls.yawObject.rotation.set(0, room.playerSpawnYaw, 0);

const overlayStart = document.getElementById('overlay-start') as HTMLElement;
const hud = document.getElementById('hud') as HTMLElement;
const btnStart = document.getElementById('btn-start') as HTMLButtonElement;
const btnRestart = document.getElementById('btn-restart') as HTMLButtonElement;
const chkReducedMotion = document.getElementById('chk-reduced-motion') as HTMLInputElement;

const WARNING_LINE =
  'Three taps through the floor. Mevrouw De Vos’s voice, barely there: “Sara. They’re on the street. Hide him.”';

const THREAT_PROXIMITY_BY_BEAT: Record<StoryBeat, number> = {
  quiet: 0,
  warning: 0.15,
  hideChild: 0.3,
  cough: 0.45,
  roomEvidence: 0.65,
  knock: 0.9,
  resolution: 0.9,
  epilogue: 0,
};

const TENSION_BY_BEAT: Record<StoryBeat, number> = {
  quiet: 0.05,
  warning: 0.3,
  hideChild: 0.45,
  cough: 0.55,
  roomEvidence: 0.7,
  knock: 0.95,
  resolution: 0.95,
  epilogue: 0.1,
};

let started = false;
let audioReady = false;
let choiceActive = false;
let latestEnding: EndingId | null = null;
let coughT = 0;

function applyReducedMotion(reduced: boolean) {
  controls.setReducedMotion(reduced);
  postfx.setReducedMotion(reduced);
}

chkReducedMotion.checked = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
applyReducedMotion(chkReducedMotion.checked);
chkReducedMotion.addEventListener('change', () => applyReducedMotion(chkReducedMotion.checked));

story.onBeatChange((beat) => {
  soundscape.setThreatProximity(THREAT_PROXIMITY_BY_BEAT[beat]);
  soundscape.playBeatCue(beat);
  lighting.setTensionLevel(TENSION_BY_BEAT[beat]);
  postfx.setGradeIntensity(TENSION_BY_BEAT[beat]);

  if (beat === 'warning') {
    ui.showSubtitle(WARNING_LINE);
  } else if (beat === 'epilogue' && latestEnding) {
    ui.showEpilogue(latestEnding);
    controls.unlock();
  }
});

story.onEnding((ending) => {
  latestEnding = ending;
  if (ending === 'calm') {
    lighting.resolveSteady();
    soundscape.resolveCalm();
  } else if (ending === 'nearMiss') {
    lighting.resolveSteady();
    soundscape.resolveNearMiss();
  } else {
    lighting.resolveGutterAndRecover();
    soundscape.resolveCostly();
  }
});

function tryInteract() {
  if (!controls.isLocked() || !started) return;
  const beat = story.getBeat();
  if (beat === 'warning' || beat === 'resolution' || beat === 'epilogue') return;

  const target = controls.getInteractionTarget(room.interactables);
  if (!target) return;
  const state = story.getExposureState();
  if (!target.isAvailable(beat, state)) return;

  if (target.id === 'door' && beat === 'knock' && !state.doorTone) {
    choiceActive = true;
    controls.unlock();
    ui.showDoorToneChoice((tone) => {
      story.chooseDoorTone(tone);
      choiceActive = false;
      controls.lock();
    });
    return;
  }

  story.handleInteract(target.id);
}

window.addEventListener('keydown', (e) => {
  if (e.code === 'KeyE') tryInteract();
});
renderer.domElement.addEventListener('mousedown', (e) => {
  if (e.button === 0 && controls.isLocked()) tryInteract();
});

controls.onLockChange((locked) => {
  if (locked) {
    overlayStart.classList.add('hidden');
    hud.classList.remove('hidden');
  } else if (!choiceActive && started) {
    overlayStart.classList.remove('hidden');
  }
});

btnStart.addEventListener('click', async () => {
  if (started) {
    controls.lock();
    return;
  }
  started = true;
  controls.lock();
  if (!audioReady) {
    await soundscape.init();
    audioReady = true;
  }
  story.start();
});

btnRestart.addEventListener('click', () => {
  window.location.reload();
});

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
  postfx.setSize(window.innerWidth, window.innerHeight);
});

const clock = new THREE.Clock();

function animate() {
  requestAnimationFrame(animate);
  const dt = Math.min(clock.getDelta(), 0.1);
  const elapsed = clock.elapsedTime;

  controls.update(dt);
  room.update(dt, elapsed);
  lighting.update(dt, elapsed);

  if (started) {
    story.update(dt);

    const beat = story.getBeat();
    if (beat === 'cough') {
      coughT = Math.min(1, coughT + dt / 2);
    } else if (coughT > 0) {
      coughT = Math.max(0, coughT - dt * 2);
    }
    if (audioReady) soundscape.setDanielCough(coughT);

    if (controls.isLocked() && beat !== 'warning' && beat !== 'resolution' && beat !== 'epilogue') {
      const target = controls.getInteractionTarget(room.interactables);
      const state = story.getExposureState();
      if (target && target.isAvailable(beat, state)) {
        ui.showInteractPrompt(target.getPromptLabel(beat, state));
      } else {
        ui.hideInteractPrompt();
      }
    } else {
      ui.hideInteractPrompt();
    }
  }

  if (audioReady) soundscape.update(dt, elapsed);

  postfx.render();
}

animate();
