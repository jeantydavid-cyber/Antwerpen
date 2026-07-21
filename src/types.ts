import type * as THREE from 'three';

export type StoryBeat =
  | 'quiet'
  | 'warning'
  | 'hideChild'
  | 'cough'
  | 'roomEvidence'
  | 'knock'
  | 'resolution'
  | 'epilogue';

export type HidingSpotId = 'hidingWardrobe' | 'hidingFloorboards' | 'hidingCellarHatch';
export type CoughActionId = 'giveHoney' | 'coverMouth' | 'wrapDeeper';
export type EvidenceItemId = 'tableBowl' | 'wallDrawing' | 'doorframeMezuzah';
export type DoorTone = 'warm' | 'silent' | 'indignant';
export type EndingId = 'calm' | 'nearMiss' | 'costly';

export type InteractableId =
  | 'candle'
  | 'honeyJar'
  | 'daniel'
  | HidingSpotId
  | EvidenceItemId
  | 'door';

export interface ExposureState {
  exposure: number;
  childDistress: number;
  hidingSpot: HidingSpotId | null;
  coughAction: CoughActionId | null;
  hiddenEvidence: EvidenceItemId[];
  doorTone: DoorTone | null;
}

export interface InteractableDef {
  id: InteractableId;
  object: THREE.Object3D;
  getPromptLabel: (beat: StoryBeat, state: ExposureState) => string;
  isAvailable: (beat: StoryBeat, state: ExposureState) => boolean;
}

export interface RoomScene {
  group: THREE.Group;
  interactables: InteractableDef[];
  candleFlameAnchor: THREE.Object3D;
  danielAnchor: THREE.Object3D;
  getHidingSpotAnchor: (id: HidingSpotId) => THREE.Object3D;
  setDanielVisible: (visible: boolean, atSpot?: HidingSpotId) => void;
  setEvidenceHidden: (id: EvidenceItemId, hidden: boolean) => void;
  playerSpawn: THREE.Vector3;
  playerSpawnYaw: number;
  colliders: Array<{ minX: number; maxX: number; minZ: number; maxZ: number }>;
  update: (dt: number, elapsed: number) => void;
}

export interface LightingSystem {
  candleLight: THREE.PointLight;
  moonLight: THREE.Light;
  setTensionLevel: (level: number) => void;
  setReducedMotion: (reduced: boolean) => void;
  resolveSteady: () => void;
  resolveGutterAndRecover: () => void;
  update: (dt: number, elapsed: number) => void;
}

export interface PostFX {
  render: () => void;
  setSize: (w: number, h: number) => void;
  setReducedMotion: (reduced: boolean) => void;
  setGradeIntensity: (level: number) => void;
}

export interface Controls {
  yawObject: THREE.Object3D;
  isLocked: () => boolean;
  lock: () => void;
  unlock: () => void;
  onLockChange: (cb: (locked: boolean) => void) => void;
  setCrouch: (crouching: boolean) => void;
  setReducedMotion: (reduced: boolean) => void;
  update: (dt: number) => void;
  getInteractionTarget: (interactables: InteractableDef[]) => InteractableDef | null;
}

export interface Soundscape {
  init: () => Promise<void>;
  setThreatProximity: (level: number) => void;
  playBeatCue: (beat: StoryBeat) => void;
  setDanielCough: (intensity: number) => void;
  resolveCalm: () => void;
  resolveNearMiss: () => void;
  resolveCostly: () => void;
  setMuted: (muted: boolean) => void;
  update: (dt: number, elapsed: number) => void;
}

export interface StorySequencer {
  getBeat: () => StoryBeat;
  getExposureState: () => Readonly<ExposureState>;
  start: () => void;
  update: (dt: number) => void;
  handleInteract: (id: InteractableId) => void;
  chooseDoorTone: (tone: DoorTone) => void;
  onBeatChange: (cb: (beat: StoryBeat, prev: StoryBeat) => void) => void;
  onEnding: (cb: (ending: EndingId) => void) => void;
}

export interface UIPrompts {
  showInteractPrompt: (label: string) => void;
  hideInteractPrompt: () => void;
  showSubtitle: (text: string, durationMs?: number) => void;
  hideSubtitle: () => void;
  showDoorToneChoice: (onChoose: (tone: DoorTone) => void) => void;
  hideDoorToneChoice: () => void;
  showEpilogue: (ending: EndingId) => void;
}

export function createInitialExposureState(): ExposureState {
  return {
    exposure: 0,
    childDistress: 0,
    hidingSpot: null,
    coughAction: null,
    hiddenEvidence: [],
    doorTone: null,
  };
}
