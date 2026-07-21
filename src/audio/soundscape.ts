import * as THREE from 'three';
import type { Soundscape, StoryBeat } from '../types';
import { clamp, lerp, smoothstep } from '../lib/utils';
import { fractalNoise1D } from '../lib/noise';

const WINDOW_ANCHOR_POS = new THREE.Vector3(0.9, 1.5, -3.2);
const DOOR_ANCHOR_POS = new THREE.Vector3(-1.5, 1.2, 3.2);

const NOISE_BUFFER_SECONDS = 4;
const SHOCK_FILTER_OPEN = 20000;

const WIND_HISS_BASE_GAIN = 0.035;
const CANDLE_HISS_GAIN = 0.018;

const TICK_INTERVAL_MS = 1000;
const TICK_JITTER_MS = 70;
const TICK_PEAK_GAIN = 0.05;

const THREAT_SMOOTH_TIME_CONSTANT = 0.7;
const ENGINE_SWELL_THRESHOLD = 0.3;
const DOG_BARK_THRESHOLD = 0.55;
const BOOTS_BURST_THRESHOLD = 0.8;
const PULSE_LOOP_THRESHOLD = 0.4;
const THRESHOLD_REARM_MARGIN = 0.12;

const COUGH_MIN_INTERVAL_S = 4.5;
const COUGH_MAX_INTERVAL_S = 11;

function createWhiteNoiseBuffer(ctx: AudioContext): AudioBuffer {
  const length = Math.floor(ctx.sampleRate * NOISE_BUFFER_SECONDS);
  const buffer = ctx.createBuffer(1, length, ctx.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < length; i++) data[i] = Math.random() * 2 - 1;
  return buffer;
}

function loopingNoiseSource(ctx: AudioContext, buffer: AudioBuffer): AudioBufferSourceNode {
  const src = ctx.createBufferSource();
  src.buffer = buffer;
  src.loop = true;
  return src;
}

function burstNoiseSource(ctx: AudioContext, buffer: AudioBuffer): AudioBufferSourceNode {
  const src = ctx.createBufferSource();
  src.buffer = buffer;
  src.loop = false;
  return src;
}

function fadeGainTo(param: AudioParam, target: number, startTime: number, duration: number): void {
  param.cancelScheduledValues(startTime);
  param.setValueAtTime(param.value, startTime);
  param.linearRampToValueAtTime(target, startTime + duration);
}

interface GraphNodes {
  noiseBuffer: AudioBuffer;
  ambientBus: GainNode;
  ambientShockFilter: BiquadFilterNode;
  windHissGain: GainNode;
  windowThreatBus: GainNode;
  windowShockFilter: BiquadFilterNode;
  doorThreatBus: GainNode;
  doorShockFilter: BiquadFilterNode;
  engineDoorGain: GainNode;
  engineWindowGain: GainNode;
  engineFilter: BiquadFilterNode;
  tensionGain: GainNode;
  tensionFilter: BiquadFilterNode;
  breathingGain: GainNode;
}

export function createSoundscape(camera: THREE.Camera, scene: THREE.Scene): Soundscape {
  const listener = new THREE.AudioListener();
  camera.add(listener);

  const windowAnchor = new THREE.Object3D();
  windowAnchor.position.copy(WINDOW_ANCHOR_POS);
  scene.add(windowAnchor);

  const doorAnchor = new THREE.Object3D();
  doorAnchor.position.copy(DOOR_ANCHOR_POS);
  scene.add(doorAnchor);

  const ambientAudio = new THREE.Audio(listener);
  listener.add(ambientAudio);

  const windowAudio = new THREE.PositionalAudio(listener);
  windowAudio.setRefDistance(1.4);
  windowAudio.setRolloffFactor(1.8);
  windowAudio.setDistanceModel('inverse');
  windowAudio.setMaxDistance(24);
  windowAnchor.add(windowAudio);

  const doorAudio = new THREE.PositionalAudio(listener);
  doorAudio.setRefDistance(1.4);
  doorAudio.setRolloffFactor(1.8);
  doorAudio.setDistanceModel('inverse');
  doorAudio.setMaxDistance(24);
  doorAnchor.add(doorAudio);

  let ctx: AudioContext | null = null;
  let nodes: GraphNodes | null = null;
  let initPromise: Promise<void> | null = null;

  let tickTimer: number | null = null;
  let tickSeed = 0;

  let pulseLoopActive = false;
  let pulseLoopTimer: number | null = null;

  let coughIntensity = 0;
  let coughLoopActive = false;
  let coughTimer: number | null = null;

  let currentLevel = 0;
  let engineSwellArmed = true;
  let dogBarkArmed = true;
  let bootsBurstArmed = true;

  // Custom synthesis chains end in a BiquadFilterNode/GainNode, not an
  // AudioScheduledSourceNode, so THREE.Audio.setNodeSource() (which is typed
  // to only accept a source node) can't take them. Connecting straight into
  // getOutput() (the panner for PositionalAudio, the gain for Audio) sidesteps
  // that and lets several layers mix into one spatialized voice per anchor.
  function buildGraph(context: AudioContext): GraphNodes {
    const noiseBuffer = createWhiteNoiseBuffer(context);

    const ambientBus = context.createGain();
    const ambientShockFilter = context.createBiquadFilter();
    ambientShockFilter.type = 'lowpass';
    ambientShockFilter.frequency.value = SHOCK_FILTER_OPEN;
    ambientBus.connect(ambientShockFilter);
    ambientShockFilter.connect(ambientAudio.getOutput());

    const windHissGain = context.createGain();
    windHissGain.gain.value = WIND_HISS_BASE_GAIN;
    const windowThreatBus = context.createGain();
    const windowShockFilter = context.createBiquadFilter();
    windowShockFilter.type = 'lowpass';
    windowShockFilter.frequency.value = SHOCK_FILTER_OPEN;
    windHissGain.connect(windowShockFilter);
    windowThreatBus.connect(windowShockFilter);
    windowShockFilter.connect(windowAudio.getOutput());

    const doorThreatBus = context.createGain();
    const doorShockFilter = context.createBiquadFilter();
    doorShockFilter.type = 'lowpass';
    doorShockFilter.frequency.value = SHOCK_FILTER_OPEN;
    doorThreatBus.connect(doorShockFilter);
    doorShockFilter.connect(doorAudio.getOutput());

    const windNoiseFilter = context.createBiquadFilter();
    windNoiseFilter.type = 'lowpass';
    windNoiseFilter.frequency.value = 1100;
    windNoiseFilter.Q.value = 0.5;
    const windSource = loopingNoiseSource(context, noiseBuffer);
    windSource.connect(windNoiseFilter);
    windNoiseFilter.connect(windHissGain);
    windSource.start();

    const windGustLfo = context.createOscillator();
    windGustLfo.frequency.value = 0.045;
    const windGustDepth = context.createGain();
    windGustDepth.gain.value = 260;
    windGustLfo.connect(windGustDepth);
    windGustDepth.connect(windNoiseFilter.frequency);
    windGustLfo.start();

    const candleFilter = context.createBiquadFilter();
    candleFilter.type = 'bandpass';
    candleFilter.frequency.value = 3200;
    candleFilter.Q.value = 0.6;
    const candleGain = context.createGain();
    candleGain.gain.value = CANDLE_HISS_GAIN;
    const candleSource = loopingNoiseSource(context, noiseBuffer);
    candleSource.playbackRate.value = 1.6;
    candleSource.connect(candleFilter);
    candleFilter.connect(candleGain);
    candleGain.connect(ambientBus);
    candleSource.start();

    const breathingFilter = context.createBiquadFilter();
    breathingFilter.type = 'lowpass';
    breathingFilter.frequency.value = 420;
    const breathingGain = context.createGain();
    breathingGain.gain.value = 0;
    const breathingSource = loopingNoiseSource(context, noiseBuffer);
    breathingSource.playbackRate.value = 0.6;
    breathingSource.connect(breathingFilter);
    breathingFilter.connect(breathingGain);
    breathingGain.connect(ambientBus);
    breathingSource.start();

    const engineOscA = context.createOscillator();
    engineOscA.type = 'sawtooth';
    engineOscA.frequency.value = 52;
    const engineOscB = context.createOscillator();
    engineOscB.type = 'sawtooth';
    engineOscB.frequency.value = 57;
    const engineFilter = context.createBiquadFilter();
    engineFilter.type = 'lowpass';
    engineFilter.frequency.value = 140;
    engineFilter.Q.value = 0.4;
    engineOscA.connect(engineFilter);
    engineOscB.connect(engineFilter);
    const engineDoorGain = context.createGain();
    engineDoorGain.gain.value = 0;
    const engineWindowGain = context.createGain();
    engineWindowGain.gain.value = 0;
    engineFilter.connect(engineDoorGain);
    engineFilter.connect(engineWindowGain);
    engineDoorGain.connect(doorThreatBus);
    engineWindowGain.connect(windowThreatBus);
    engineOscA.start();
    engineOscB.start();

    const tensionFilter = context.createBiquadFilter();
    tensionFilter.type = 'bandpass';
    tensionFilter.frequency.value = 280;
    tensionFilter.Q.value = 0.8;
    const tensionGain = context.createGain();
    tensionGain.gain.value = 0;
    const tensionSource = loopingNoiseSource(context, noiseBuffer);
    tensionSource.connect(tensionFilter);
    tensionFilter.connect(tensionGain);
    tensionGain.connect(doorThreatBus);
    tensionSource.start();

    return {
      noiseBuffer,
      ambientBus,
      ambientShockFilter,
      windHissGain,
      windowThreatBus,
      windowShockFilter,
      doorThreatBus,
      doorShockFilter,
      engineDoorGain,
      engineWindowGain,
      engineFilter,
      tensionGain,
      tensionFilter,
      breathingGain,
    };
  }

  function fireTick(): void {
    if (!ctx || !nodes) return;
    const t0 = ctx.currentTime;
    const osc = ctx.createOscillator();
    osc.type = 'square';
    osc.frequency.value = 1700;
    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.value = 1600;
    filter.Q.value = 7;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, t0);
    gain.gain.linearRampToValueAtTime(TICK_PEAK_GAIN, t0 + 0.002);
    gain.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.05);
    osc.connect(filter);
    filter.connect(gain);
    gain.connect(nodes.ambientBus);
    osc.start(t0);
    osc.stop(t0 + 0.06);
    osc.onended = () => {
      osc.disconnect();
      filter.disconnect();
      gain.disconnect();
    };
  }

  function scheduleNextTick(): void {
    if (!ctx) return;
    fireTick();
    const jitter = (fractalNoise1D(tickSeed) - 0.5) * 2 * TICK_JITTER_MS;
    tickSeed += 0.41;
    tickTimer = window.setTimeout(scheduleNextTick, TICK_INTERVAL_MS + jitter);
  }

  function scheduleFootstepThumpAt(time: number, peak: number): void {
    if (!ctx || !nodes) return;
    const src = burstNoiseSource(ctx, nodes.noiseBuffer);
    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 190;
    filter.Q.value = 0.3;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, time);
    gain.gain.linearRampToValueAtTime(peak, time + 0.012);
    gain.gain.exponentialRampToValueAtTime(0.0001, time + 0.15);
    src.connect(filter);
    filter.connect(gain);
    gain.connect(nodes.doorThreatBus);
    src.start(time);
    src.stop(time + 0.17);
    src.onended = () => {
      src.disconnect();
      filter.disconnect();
      gain.disconnect();
    };
  }

  function startPulseLoop(): void {
    if (pulseLoopActive) return;
    pulseLoopActive = true;
    scheduleNextPulse();
  }

  function stopPulseLoop(): void {
    pulseLoopActive = false;
    if (pulseLoopTimer !== null) {
      window.clearTimeout(pulseLoopTimer);
      pulseLoopTimer = null;
    }
  }

  function scheduleNextPulse(): void {
    if (!pulseLoopActive || !ctx) return;
    const urgency = smoothstep(PULSE_LOOP_THRESHOLD, 1, currentLevel);
    scheduleFootstepThumpAt(ctx.currentTime, lerp(0.06, 0.15, urgency));
    const interval = lerp(1.05, 0.48, urgency);
    pulseLoopTimer = window.setTimeout(scheduleNextPulse, interval * 1000);
  }

  function fireBootsBurst(): void {
    if (!ctx) return;
    const t0 = ctx.currentTime;
    const steps = 5;
    for (let i = 0; i < steps; i++) {
      scheduleFootstepThumpAt(t0 + i * 0.4, lerp(0.09, 0.18, i / (steps - 1)));
    }
  }

  function fireDogBark(): void {
    if (!ctx || !nodes) return;
    const t0 = ctx.currentTime;
    const osc = ctx.createOscillator();
    osc.type = 'sawtooth';
    osc.frequency.setValueAtTime(620, t0);
    osc.frequency.exponentialRampToValueAtTime(340, t0 + 0.13);
    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 1400;
    const delay = ctx.createDelay(0.5);
    delay.delayTime.value = 0.16;
    const feedback = ctx.createGain();
    feedback.gain.value = 0.22;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, t0);
    gain.gain.linearRampToValueAtTime(0.16, t0 + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.22);

    osc.connect(filter);
    filter.connect(gain);
    gain.connect(nodes.doorThreatBus);
    gain.connect(delay);
    delay.connect(feedback);
    feedback.connect(delay);
    delay.connect(nodes.doorThreatBus);

    osc.start(t0);
    osc.stop(t0 + 0.24);
    osc.onended = () => {
      osc.disconnect();
      filter.disconnect();
      gain.disconnect();
      delay.disconnect();
      feedback.disconnect();
    };
  }

  function fireEngineSwell(): void {
    if (!ctx || !nodes) return;
    const t0 = ctx.currentTime;
    const duration = 1.9;
    const osc = ctx.createOscillator();
    osc.type = 'sawtooth';
    osc.frequency.setValueAtTime(48, t0);
    osc.frequency.linearRampToValueAtTime(64, t0 + duration * 0.5);
    osc.frequency.linearRampToValueAtTime(44, t0 + duration);
    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.setValueAtTime(180, t0);
    filter.frequency.linearRampToValueAtTime(620, t0 + duration * 0.55);
    filter.frequency.linearRampToValueAtTime(150, t0 + duration);
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, t0);
    gain.gain.linearRampToValueAtTime(0.22, t0 + duration * 0.5);
    gain.gain.exponentialRampToValueAtTime(0.0001, t0 + duration);
    osc.connect(filter);
    filter.connect(gain);
    gain.connect(nodes.doorThreatBus);
    osc.start(t0);
    osc.stop(t0 + duration + 0.05);
    osc.onended = () => {
      osc.disconnect();
      filter.disconnect();
      gain.disconnect();
    };
  }

  function scheduleKnockRapAt(time: number): void {
    if (!ctx || !nodes) return;
    const bodyOsc = ctx.createOscillator();
    bodyOsc.type = 'triangle';
    bodyOsc.frequency.value = 130;
    const bodyGain = ctx.createGain();
    bodyGain.gain.setValueAtTime(0.0001, time);
    bodyGain.gain.linearRampToValueAtTime(0.34, time + 0.006);
    bodyGain.gain.exponentialRampToValueAtTime(0.0001, time + 0.18);
    bodyOsc.connect(bodyGain);
    bodyGain.connect(nodes.doorThreatBus);
    bodyOsc.start(time);
    bodyOsc.stop(time + 0.2);
    bodyOsc.onended = () => {
      bodyOsc.disconnect();
      bodyGain.disconnect();
    };

    const noise = burstNoiseSource(ctx, nodes.noiseBuffer);
    const noiseFilter = ctx.createBiquadFilter();
    noiseFilter.type = 'bandpass';
    noiseFilter.frequency.value = 1100;
    noiseFilter.Q.value = 2.2;
    const noiseGain = ctx.createGain();
    noiseGain.gain.setValueAtTime(0.0001, time);
    noiseGain.gain.linearRampToValueAtTime(0.18, time + 0.003);
    noiseGain.gain.exponentialRampToValueAtTime(0.0001, time + 0.05);
    noise.connect(noiseFilter);
    noiseFilter.connect(noiseGain);
    noiseGain.connect(nodes.doorThreatBus);
    noise.start(time);
    noise.stop(time + 0.06);
    noise.onended = () => {
      noise.disconnect();
      noiseFilter.disconnect();
      noiseGain.disconnect();
    };
  }

  function fireKnock(): void {
    if (!ctx) return;
    stopPulseLoop();
    const t0 = ctx.currentTime;
    scheduleFootstepThumpAt(t0, 0.2);
    const knockStart = t0 + 0.35;
    const raps = 3;
    for (let i = 0; i < raps; i++) {
      scheduleKnockRapAt(knockStart + i * 0.46);
    }
  }

  function fireWarningTaps(): void {
    if (!ctx || !nodes) return;
    const t0 = ctx.currentTime;
    const taps = 3;
    for (let i = 0; i < taps; i++) {
      const time = t0 + i * 0.32 + Math.random() * 0.03;
      const src = burstNoiseSource(ctx, nodes.noiseBuffer);
      const filter = ctx.createBiquadFilter();
      filter.type = 'lowpass';
      filter.frequency.value = 260;
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(0.0001, time);
      gain.gain.linearRampToValueAtTime(0.075, time + 0.008);
      gain.gain.exponentialRampToValueAtTime(0.0001, time + 0.1);
      src.connect(filter);
      filter.connect(gain);
      gain.connect(nodes.ambientBus);
      src.start(time);
      src.stop(time + 0.12);
      src.onended = () => {
        src.disconnect();
        filter.disconnect();
        gain.disconnect();
      };
    }
  }

  function scheduleCoughBurstAt(time: number, peak: number): void {
    if (!ctx || !nodes) return;
    const src = burstNoiseSource(ctx, nodes.noiseBuffer);
    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.value = 480;
    filter.Q.value = 1.1;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, time);
    gain.gain.linearRampToValueAtTime(peak, time + 0.035);
    gain.gain.exponentialRampToValueAtTime(0.0001, time + 0.26);
    src.connect(filter);
    filter.connect(gain);
    gain.connect(nodes.ambientBus);
    src.start(time);
    src.stop(time + 0.28);
    src.onended = () => {
      src.disconnect();
      filter.disconnect();
      gain.disconnect();
    };
  }

  function fireCough(): void {
    if (!ctx) return;
    const t0 = ctx.currentTime;
    const peak = lerp(0.05, 0.12, coughIntensity);
    scheduleCoughBurstAt(t0, peak);
    if (coughIntensity > 0.4) {
      scheduleCoughBurstAt(t0 + 0.24, peak * 0.4);
    }
  }

  function scheduleNextCough(): void {
    if (!coughLoopActive) return;
    const wait = lerp(COUGH_MAX_INTERVAL_S, COUGH_MIN_INTERVAL_S, coughIntensity) + Math.random() * 2;
    coughTimer = window.setTimeout(() => {
      fireCough();
      scheduleNextCough();
    }, wait * 1000);
  }

  function fireClatter(): void {
    if (!ctx || !nodes) return;
    const t0 = ctx.currentTime;
    const hits: Array<[number, number, number]> = [
      [0, 620, 0.24],
      [0.08, 480, 0.16],
      [0.15, 720, 0.1],
      [0.24, 390, 0.06],
    ];
    for (const [offset, freq, peak] of hits) {
      const time = t0 + offset;
      const src = burstNoiseSource(ctx, nodes.noiseBuffer);
      const filter = ctx.createBiquadFilter();
      filter.type = 'bandpass';
      filter.frequency.value = freq;
      filter.Q.value = 3;
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(0.0001, time);
      gain.gain.linearRampToValueAtTime(peak, time + 0.004);
      gain.gain.exponentialRampToValueAtTime(0.0001, time + 0.09);
      src.connect(filter);
      filter.connect(gain);
      gain.connect(nodes.doorThreatBus);
      src.start(time);
      src.stop(time + 0.1);
      src.onended = () => {
        src.disconnect();
        filter.disconnect();
        gain.disconnect();
      };
    }
  }

  function fireMuffledMurmur(): void {
    if (!ctx || !nodes) return;
    const t0 = ctx.currentTime + 0.3;
    const duration = 1.1;
    const oscA = ctx.createOscillator();
    oscA.type = 'sawtooth';
    oscA.frequency.value = 130;
    const oscB = ctx.createOscillator();
    oscB.type = 'sawtooth';
    oscB.frequency.value = 155;
    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.value = 360;
    filter.Q.value = 1.4;
    const lfo = ctx.createOscillator();
    lfo.frequency.value = 5.5;
    const lfoDepth = ctx.createGain();
    lfoDepth.gain.value = 0.02;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, t0);
    gain.gain.linearRampToValueAtTime(0.05, t0 + 0.15);
    gain.gain.linearRampToValueAtTime(0.0001, t0 + duration);
    lfo.connect(lfoDepth);
    lfoDepth.connect(gain.gain);
    oscA.connect(filter);
    oscB.connect(filter);
    filter.connect(gain);
    gain.connect(nodes.doorThreatBus);
    oscA.start(t0);
    oscB.start(t0);
    lfo.start(t0);
    oscA.stop(t0 + duration + 0.05);
    oscB.stop(t0 + duration + 0.05);
    lfo.stop(t0 + duration + 0.05);
    oscA.onended = () => {
      oscA.disconnect();
      oscB.disconnect();
      filter.disconnect();
      gain.disconnect();
      lfo.disconnect();
      lfoDepth.disconnect();
    };
  }

  function fireTenseSwell(): void {
    if (!ctx || !nodes) return;
    const t0 = ctx.currentTime;
    const duration = 0.85;
    const src = burstNoiseSource(ctx, nodes.noiseBuffer);
    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(320, t0);
    filter.frequency.linearRampToValueAtTime(1500, t0 + duration);
    filter.Q.value = 0.9;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, t0);
    gain.gain.linearRampToValueAtTime(0.26, t0 + duration * 0.85);
    gain.gain.linearRampToValueAtTime(0.0001, t0 + duration + 0.1);
    src.connect(filter);
    filter.connect(gain);
    gain.connect(nodes.doorThreatBus);
    src.start(t0);
    src.stop(t0 + duration + 0.15);
    src.onended = () => {
      src.disconnect();
      filter.disconnect();
      gain.disconnect();
    };
  }

  function fireRingTone(startTime: number, totalDuration: number): void {
    if (!ctx) return;
    const oscA = ctx.createOscillator();
    oscA.type = 'sine';
    oscA.frequency.value = 2650;
    const oscB = ctx.createOscillator();
    oscB.type = 'sine';
    oscB.frequency.value = 2668;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, startTime);
    gain.gain.linearRampToValueAtTime(0.022, startTime + 0.5);
    gain.gain.setValueAtTime(0.022, startTime + totalDuration - 1.1);
    gain.gain.linearRampToValueAtTime(0.0001, startTime + totalDuration);
    oscA.connect(gain);
    oscB.connect(gain);
    gain.connect(ambientAudio.getOutput());
    oscA.start(startTime);
    oscB.start(startTime);
    oscA.stop(startTime + totalDuration + 0.1);
    oscB.stop(startTime + totalDuration + 0.1);
    oscA.onended = () => {
      oscA.disconnect();
      oscB.disconnect();
      gain.disconnect();
    };
  }

  async function doInit(): Promise<void> {
    const context = listener.context;
    if (context.state !== 'running') {
      await context.resume();
    }
    ctx = context;
    nodes = buildGraph(context);
    scheduleNextTick();
  }

  function init(): Promise<void> {
    if (!initPromise) initPromise = doInit();
    return initPromise;
  }

  function setThreatProximity(levelInput: number): void {
    const level = clamp(levelInput, 0, 1);
    currentLevel = level;
    if (!ctx || !nodes) return;
    const now = ctx.currentTime;

    nodes.engineDoorGain.gain.setTargetAtTime(lerp(0.015, 0.24, level), now, THREAT_SMOOTH_TIME_CONSTANT);
    nodes.engineWindowGain.gain.setTargetAtTime(lerp(0.008, 0.05, level), now, THREAT_SMOOTH_TIME_CONSTANT);
    nodes.engineFilter.frequency.setTargetAtTime(lerp(130, 900, level), now, THREAT_SMOOTH_TIME_CONSTANT);
    nodes.tensionGain.gain.setTargetAtTime(lerp(0, 0.15, level), now, THREAT_SMOOTH_TIME_CONSTANT);
    nodes.tensionFilter.frequency.setTargetAtTime(lerp(260, 1500, level), now, THREAT_SMOOTH_TIME_CONSTANT);

    if (level >= ENGINE_SWELL_THRESHOLD && engineSwellArmed) {
      engineSwellArmed = false;
      fireEngineSwell();
    } else if (level < ENGINE_SWELL_THRESHOLD - THRESHOLD_REARM_MARGIN) {
      engineSwellArmed = true;
    }

    if (level >= DOG_BARK_THRESHOLD && dogBarkArmed) {
      dogBarkArmed = false;
      fireDogBark();
    } else if (level < DOG_BARK_THRESHOLD - THRESHOLD_REARM_MARGIN) {
      dogBarkArmed = true;
    }

    if (level >= BOOTS_BURST_THRESHOLD && bootsBurstArmed) {
      bootsBurstArmed = false;
      fireBootsBurst();
    } else if (level < BOOTS_BURST_THRESHOLD - THRESHOLD_REARM_MARGIN) {
      bootsBurstArmed = true;
    }

    if (level >= PULSE_LOOP_THRESHOLD) {
      startPulseLoop();
    } else if (level < PULSE_LOOP_THRESHOLD - THRESHOLD_REARM_MARGIN) {
      stopPulseLoop();
    }
  }

  function playBeatCue(beat: StoryBeat): void {
    if (!ctx) return;
    if (beat === 'warning') {
      fireWarningTaps();
    } else if (beat === 'knock') {
      fireKnock();
    }
  }

  function setDanielCough(intensityInput: number): void {
    const intensity = clamp(intensityInput, 0, 1);
    coughIntensity = intensity;
    if (!ctx || !nodes) return;
    const now = ctx.currentTime;
    nodes.breathingGain.gain.setTargetAtTime(intensity > 0 ? lerp(0.006, 0.026, intensity) : 0, now, 0.9);
    if (intensity > 0 && !coughLoopActive) {
      coughLoopActive = true;
      scheduleNextCough();
    } else if (intensity <= 0 && coughLoopActive) {
      coughLoopActive = false;
      if (coughTimer !== null) {
        window.clearTimeout(coughTimer);
        coughTimer = null;
      }
    }
  }

  function resolveCalm(): void {
    if (!ctx || !nodes) return;
    stopPulseLoop();
    const now = ctx.currentTime;
    fadeGainTo(nodes.doorThreatBus.gain, 0, now, 3.4);
    fadeGainTo(nodes.windowThreatBus.gain, 0, now, 3.4);
  }

  function resolveNearMiss(): void {
    if (!ctx || !nodes) return;
    fireClatter();
    fireMuffledMurmur();
    stopPulseLoop();
    const now = ctx.currentTime;
    const holdBefore = 0.55;
    fadeGainTo(nodes.doorThreatBus.gain, 0, now + holdBefore, 2.4);
    fadeGainTo(nodes.windowThreatBus.gain, 0, now + holdBefore, 2.4);
  }

  function resolveCostly(): void {
    if (!ctx || !nodes) return;
    stopPulseLoop();
    const now = ctx.currentTime;
    fireTenseSwell();

    const shockStart = now + 0.95;
    const closeDuration = 0.55;
    const holdDuration = 3.6;
    const recoverDuration = 2.8;

    for (const filter of [nodes.doorShockFilter, nodes.windowShockFilter, nodes.ambientShockFilter]) {
      filter.frequency.cancelScheduledValues(now);
      filter.frequency.setValueAtTime(filter.frequency.value, shockStart);
      filter.frequency.linearRampToValueAtTime(420, shockStart + closeDuration);
      filter.frequency.setValueAtTime(420, shockStart + closeDuration + holdDuration);
      filter.frequency.linearRampToValueAtTime(
        SHOCK_FILTER_OPEN,
        shockStart + closeDuration + holdDuration + recoverDuration,
      );
    }

    fireRingTone(shockStart + closeDuration * 0.4, closeDuration + holdDuration + recoverDuration * 0.4);

    fadeGainTo(nodes.doorThreatBus.gain, 0, shockStart + closeDuration, 1.6);
    fadeGainTo(nodes.windowThreatBus.gain, 0, shockStart + closeDuration, 1.6);
  }

  function setMuted(muted: boolean): void {
    const g = listener.gain.gain;
    const now = listener.context.currentTime;
    g.cancelScheduledValues(now);
    g.setValueAtTime(g.value, now);
    g.linearRampToValueAtTime(muted ? 0 : 1, now + 0.15);
  }

  function update(_dt: number, _elapsed: number): void {}

  return {
    init,
    setThreatProximity,
    playBeatCue,
    setDanielCough,
    resolveCalm,
    resolveNearMiss,
    resolveCostly,
    setMuted,
    update,
  };
}
