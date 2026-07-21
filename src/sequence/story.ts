import type {
  CoughActionId,
  DoorTone,
  EndingId,
  EvidenceItemId,
  ExposureState,
  HidingSpotId,
  InteractableId,
  RoomScene,
  StoryBeat,
  StorySequencer,
} from '../types';
import { createInitialExposureState } from '../types';

const QUIET_EXPLORE_TARGET = 2;
const QUIET_FALLBACK_SECONDS = 25;
const WARNING_HOLD_SECONDS = 5;
const COUGH_FALLBACK_SECONDS = 20;
const EVIDENCE_GRACE_SECONDS = 14;
const RESOLUTION_HOLD_SECONDS = 7;

const HIDING_SPOT_DELTAS: Record<HidingSpotId, { exposure: number; distress: number }> = {
  hidingWardrobe: { exposure: 0.12, distress: -0.1 },
  hidingFloorboards: { exposure: 0.02, distress: 0.08 },
  hidingCellarHatch: { exposure: -0.1, distress: 0.15 },
};

const COUGH_DELTAS: Record<CoughActionId, { exposure: number; distress: number }> = {
  giveHoney: { exposure: 0, distress: -0.2 },
  coverMouth: { exposure: -0.08, distress: 0.18 },
  wrapDeeper: { exposure: -0.03, distress: 0.06 },
};

const EVIDENCE_HIDE_EXPOSURE = -0.05;

const DOOR_TONE_DELTAS: Record<DoorTone, number> = {
  warm: -0.15,
  silent: 0.03,
  indignant: 0.15,
};

const CALM_THRESHOLD = -0.12;
const COSTLY_THRESHOLD = 0.22;

export function createStorySequencer(room: RoomScene): StorySequencer {
  let beat: StoryBeat = 'quiet';
  let elapsedInBeat = 0;
  let started = false;
  let ending: EndingId | null = null;

  const state: ExposureState = createInitialExposureState();
  const exploredIds = new Set<InteractableId>();

  const beatListeners: Array<(b: StoryBeat, prev: StoryBeat) => void> = [];
  const endingListeners: Array<(e: EndingId) => void> = [];

  function goTo(next: StoryBeat) {
    const prev = beat;
    beat = next;
    elapsedInBeat = 0;
    for (const cb of beatListeners) cb(next, prev);
  }

  function resolveEnding() {
    const effective = state.exposure + state.childDistress * 0.15;
    if (effective <= CALM_THRESHOLD) ending = 'calm';
    else if (effective <= COSTLY_THRESHOLD) ending = 'nearMiss';
    else ending = 'costly';
    for (const cb of endingListeners) cb(ending);
  }

  function handleQuietInteract(id: InteractableId) {
    if (id === 'candle' || id === 'honeyJar' || id === 'daniel') {
      exploredIds.add(id);
    }
  }

  function handleHideChildInteract(id: InteractableId) {
    if (id !== 'hidingWardrobe' && id !== 'hidingFloorboards' && id !== 'hidingCellarHatch') return;
    const spot = id as HidingSpotId;
    const delta = HIDING_SPOT_DELTAS[spot];
    state.hidingSpot = spot;
    state.exposure += delta.exposure;
    state.childDistress = Math.max(0, state.childDistress + delta.distress);
    room.setDanielVisible(true, spot);
    goTo('cough');
  }

  function handleCoughInteract(id: InteractableId) {
    let action: CoughActionId | null = null;
    if (id === 'honeyJar') action = 'giveHoney';
    else if (id === 'daniel') action = 'coverMouth';
    else if (state.hidingSpot && id === state.hidingSpot) action = 'wrapDeeper';
    if (!action) return;
    resolveCoughAction(action);
  }

  function resolveCoughAction(action: CoughActionId) {
    const delta = COUGH_DELTAS[action];
    state.coughAction = action;
    state.exposure += delta.exposure;
    state.childDistress = Math.max(0, Math.min(1, state.childDistress + delta.distress));
    goTo('roomEvidence');
  }

  function handleRoomEvidenceInteract(id: InteractableId) {
    if (id !== 'tableBowl' && id !== 'wallDrawing' && id !== 'doorframeMezuzah') return;
    const item = id as EvidenceItemId;
    const alreadyHidden = state.hiddenEvidence.includes(item);
    if (alreadyHidden) {
      state.hiddenEvidence = state.hiddenEvidence.filter((e) => e !== item);
      state.exposure -= EVIDENCE_HIDE_EXPOSURE;
      room.setEvidenceHidden(item, false);
    } else {
      state.hiddenEvidence = [...state.hiddenEvidence, item];
      state.exposure += EVIDENCE_HIDE_EXPOSURE;
      room.setEvidenceHidden(item, true);
    }
  }

  function handleKnockInteract(_id: InteractableId) {
    // The door itself is resolved via chooseDoorTone(), called directly
    // by the host once the player opens it — not through handleInteract.
  }

  return {
    getBeat: () => beat,
    getExposureState: () => state,

    start() {
      if (started) return;
      started = true;
      goTo('quiet');
    },

    update(dt: number) {
      if (!started) return;
      elapsedInBeat += dt;

      if (beat === 'quiet') {
        if (exploredIds.size >= QUIET_EXPLORE_TARGET || elapsedInBeat >= QUIET_FALLBACK_SECONDS) {
          goTo('warning');
        }
      } else if (beat === 'warning') {
        if (elapsedInBeat >= WARNING_HOLD_SECONDS) {
          goTo('hideChild');
        }
      } else if (beat === 'cough') {
        if (elapsedInBeat >= COUGH_FALLBACK_SECONDS) {
          resolveCoughAction('wrapDeeper');
        }
      } else if (beat === 'roomEvidence') {
        if (elapsedInBeat >= EVIDENCE_GRACE_SECONDS) {
          goTo('knock');
        }
      } else if (beat === 'resolution') {
        if (elapsedInBeat >= RESOLUTION_HOLD_SECONDS) {
          goTo('epilogue');
        }
      }
    },

    handleInteract(id: InteractableId) {
      if (!started) return;
      switch (beat) {
        case 'quiet':
          handleQuietInteract(id);
          break;
        case 'hideChild':
          handleHideChildInteract(id);
          break;
        case 'cough':
          handleCoughInteract(id);
          break;
        case 'roomEvidence':
          handleRoomEvidenceInteract(id);
          break;
        case 'knock':
          handleKnockInteract(id);
          break;
        default:
          break;
      }
    },

    chooseDoorTone(tone: DoorTone) {
      if (beat !== 'knock' || state.doorTone) return;
      state.doorTone = tone;
      state.exposure += DOOR_TONE_DELTAS[tone];
      goTo('resolution');
      resolveEnding();
    },

    onBeatChange(cb) {
      beatListeners.push(cb);
    },

    onEnding(cb) {
      endingListeners.push(cb);
    },
  };
}
