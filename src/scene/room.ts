import * as THREE from 'three';
import type {
  EvidenceItemId,
  ExposureState,
  HidingSpotId,
  InteractableDef,
  RoomScene,
  StoryBeat,
} from '../types';
import { PALETTE } from '../palette';
import { fractalNoise1D } from '../lib/noise';
import { clamp, lerp } from '../lib/utils';

const ROOM_HALF_X = 3;
const ROOM_HALF_Z = 2.5;
const CEILING_Y = 2.8;
const WALL_T = 0.15;

const WINDOW_X_MIN = 0.35;
const WINDOW_X_MAX = 1.45;
const WINDOW_Y_MIN = 1.0;
const WINDOW_Y_MAX = 2.1;

const NORTH_WALL_Z = -ROOM_HALF_Z;
const SOUTH_WALL_Z = ROOM_HALF_Z;

const DOOR_X_MIN = -1.975;
const DOOR_X_MAX = -1.025;
const DOOR_Y_MAX = 2.05;

const TABLE_CENTER = new THREE.Vector3(-0.6, 0, -0.9);
const TABLE_TOP_Y = 0.75;
const TABLE_SIZE = { x: 0.9, z: 0.55 };

const CANDLE_POS = new THREE.Vector3(-0.6, TABLE_TOP_Y, -0.9);
const CANDLE_HEIGHT = 0.13;

const DANIEL_DEFAULT_POS = new THREE.Vector3(-0.3, 0, -0.5);

const WARDROBE_CENTER = new THREE.Vector3(-2.75, 0, -1.4);
const WARDROBE_SIZE = { x: 0.5, y: 1.9, z: 1.0 };

const RUG_CENTER = new THREE.Vector3(0.9, 0, 1.1);
const RUG_SIZE = { x: 1.2, z: 0.9 };

const HATCH_CENTER = new THREE.Vector3(2.3, 0, 1.9);
const HATCH_SIZE = 0.7;

function createCanvas(size: number): { canvas: HTMLCanvasElement; ctx: CanvasRenderingContext2D } {
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('2d context unavailable');
  return { canvas, ctx };
}

function hexToRgbString(hex: number): string {
  const r = (hex >> 16) & 255;
  const g = (hex >> 8) & 255;
  const b = hex & 255;
  return `${r}, ${g}, ${b}`;
}

function shadeColor(hex: string, factor: number): string {
  const c = new THREE.Color(hex);
  c.multiplyScalar(factor);
  return `rgb(${Math.round(c.r * 255)}, ${Math.round(c.g * 255)}, ${Math.round(c.b * 255)})`;
}

function buildWoodTexture(): THREE.CanvasTexture {
  const size = 512;
  const { canvas, ctx } = createCanvas(size);
  ctx.fillStyle = '#241a12';
  ctx.fillRect(0, 0, size, size);
  const plankCount = 9;
  const plankHeight = size / plankCount;
  for (let p = 0; p < plankCount; p++) {
    const y = p * plankHeight;
    const shade = 0.7 + fractalNoise1D(p * 3.7) * 0.4;
    ctx.fillStyle = shadeColor('#4a3626', shade);
    ctx.fillRect(0, y, size, plankHeight - 2);
    for (let x = 0; x < size; x += 3) {
      const grain = fractalNoise1D(x * 0.045 + p * 11.3, 3);
      ctx.fillStyle = `rgba(18, 12, 8, ${0.04 + grain * 0.14})`;
      ctx.fillRect(x, y, 3, plankHeight - 2);
    }
    for (let i = 0; i < 3; i++) {
      const wx = fractalNoise1D(p * 5.9 + i * 2.1) * size;
      const ww = 10 + fractalNoise1D(p * 8.1 + i) * 26;
      ctx.fillStyle = 'rgba(10, 7, 5, 0.18)';
      ctx.fillRect(wx, y + 2, ww, plankHeight - 6);
    }
    ctx.fillStyle = 'rgba(0, 0, 0, 0.55)';
    ctx.fillRect(0, y + plankHeight - 2, size, 2);
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = THREE.RepeatWrapping;
  texture.wrapT = THREE.RepeatWrapping;
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function buildPlasterTexture(): THREE.CanvasTexture {
  const size = 512;
  const { canvas, ctx } = createCanvas(size);
  ctx.fillStyle = '#1c2226';
  ctx.fillRect(0, 0, size, size);
  for (let i = 0; i < 1400; i++) {
    const x = Math.random() * size;
    const y = Math.random() * size;
    const n = fractalNoise1D((x + y) * 0.012, 4);
    const shade = 0.6 + n * 0.6;
    ctx.fillStyle = shadeColor('#333c43', shade);
    const r = 1 + Math.random() * 2.5;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.strokeStyle = 'rgba(8, 10, 12, 0.55)';
  ctx.lineWidth = 1;
  for (let c = 0; c < 7; c++) {
    let x = Math.random() * size;
    let y = Math.random() * size;
    ctx.beginPath();
    ctx.moveTo(x, y);
    const segments = 8 + Math.floor(Math.random() * 10);
    for (let s = 0; s < segments; s++) {
      x += (Math.random() - 0.5) * 44;
      y += (Math.random() - 0.5) * 44;
      ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = THREE.RepeatWrapping;
  texture.wrapT = THREE.RepeatWrapping;
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function buildFrostTexture(): THREE.CanvasTexture {
  const size = 512;
  const { canvas, ctx } = createCanvas(size);
  ctx.clearRect(0, 0, size, size);
  const rgb = hexToRgbString(PALETTE.dirtySnow);
  for (let i = 0; i < 260; i++) {
    let x: number;
    let y: number;
    if (Math.random() < 0.75) {
      const side = Math.floor(Math.random() * 4);
      const t = Math.random() * size;
      const depth = Math.random() * 100;
      if (side === 0) { x = t; y = depth; }
      else if (side === 1) { x = t; y = size - depth; }
      else if (side === 2) { x = depth; y = t; }
      else { x = size - depth; y = t; }
    } else {
      x = Math.random() * size;
      y = Math.random() * size;
    }
    const r = 6 + Math.random() * 28;
    const alpha = 0.08 + Math.random() * 0.24;
    const gradient = ctx.createRadialGradient(x, y, 0, x, y, r);
    gradient.addColorStop(0, `rgba(${rgb}, ${alpha})`);
    gradient.addColorStop(1, `rgba(${rgb}, 0)`);
    ctx.fillStyle = gradient;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function buildWoolTexture(): THREE.CanvasTexture {
  const size = 256;
  const { canvas, ctx } = createCanvas(size);
  ctx.fillStyle = '#2b3138';
  ctx.fillRect(0, 0, size, size);
  for (let y = 0; y < size; y += 3) {
    const shade = 0.75 + fractalNoise1D(y * 0.08) * 0.3;
    ctx.fillStyle = shadeColor('#3c444c', shade);
    ctx.fillRect(0, y, size, 2);
  }
  for (let i = 0; i < 500; i++) {
    ctx.fillStyle = `rgba(10, 12, 14, ${Math.random() * 0.12})`;
    ctx.fillRect(Math.random() * size, Math.random() * size, 2, 1);
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function buildDrawingTexture(): THREE.CanvasTexture {
  const size = 256;
  const { canvas, ctx } = createCanvas(size);
  ctx.fillStyle = '#e9dfc4';
  ctx.fillRect(0, 0, size, size);
  for (let i = 0; i < 220; i++) {
    ctx.fillStyle = `rgba(170, 150, 110, ${Math.random() * 0.06})`;
    ctx.fillRect(Math.random() * size, Math.random() * size, 2, 2);
  }
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const sunColor = `rgb(${hexToRgbString(PALETTE.candleAmber)})`;
  ctx.strokeStyle = sunColor;
  ctx.lineWidth = 4;
  ctx.beginPath();
  ctx.arc(size * 0.76, size * 0.22, 20, 0, Math.PI * 2);
  ctx.stroke();
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * Math.PI * 2;
    ctx.beginPath();
    ctx.moveTo(size * 0.76 + Math.cos(a) * 26, size * 0.22 + Math.sin(a) * 26);
    ctx.lineTo(size * 0.76 + Math.cos(a) * 38, size * 0.22 + Math.sin(a) * 38);
    ctx.stroke();
  }

  ctx.strokeStyle = '#8a5a34';
  ctx.lineWidth = 5;
  ctx.strokeRect(size * 0.2, size * 0.56, size * 0.32, size * 0.28);
  ctx.beginPath();
  ctx.moveTo(size * 0.16, size * 0.56);
  ctx.lineTo(size * 0.36, size * 0.33);
  ctx.lineTo(size * 0.56, size * 0.56);
  ctx.stroke();
  ctx.strokeStyle = '#caa25c';
  ctx.lineWidth = 4;
  ctx.strokeRect(size * 0.3, size * 0.68, size * 0.08, size * 0.14);

  ctx.strokeStyle = '#5c6e4a';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(size * 0.08, size * 0.84);
  ctx.lineTo(size * 0.92, size * 0.84);
  ctx.stroke();

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function buildSpriteTexture(): THREE.CanvasTexture {
  const size = 64;
  const { canvas, ctx } = createCanvas(size);
  const gradient = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  gradient.addColorStop(0, 'rgba(255, 255, 255, 1)');
  gradient.addColorStop(0.6, 'rgba(255, 255, 255, 0.4)');
  gradient.addColorStop(1, 'rgba(255, 255, 255, 0)');
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, size, size);
  return new THREE.CanvasTexture(canvas);
}

export function createRoomScene(): RoomScene {
  const group = new THREE.Group();

  const woodTexture = buildWoodTexture();
  woodTexture.repeat.set(2, 2);
  const plasterTexture = buildPlasterTexture();
  plasterTexture.repeat.set(2, 1.4);
  const woolTexture = buildWoolTexture();
  const frostTexture = buildFrostTexture();
  const drawingTexture = buildDrawingTexture();
  const spriteTexture = buildSpriteTexture();

  const floorMaterial = new THREE.MeshStandardMaterial({
    map: woodTexture,
    roughness: 0.95,
    metalness: 0.02,
  });
  const wallMaterial = new THREE.MeshStandardMaterial({
    map: plasterTexture,
    color: new THREE.Color(PALETTE.coalBlueGrey).multiplyScalar(0.55),
    roughness: 1,
    metalness: 0,
  });
  const trimWoodMaterial = new THREE.MeshStandardMaterial({
    color: 0x2a1e15,
    roughness: 0.85,
    metalness: 0.05,
  });
  const brassMaterial = new THREE.MeshStandardMaterial({
    color: 0x7c6236,
    roughness: 0.42,
    metalness: 0.62,
  });
  const waxMaterial = new THREE.MeshStandardMaterial({
    color: 0xdccfa8,
    roughness: 0.55,
    metalness: 0,
  });
  const ceramicMaterial = new THREE.MeshStandardMaterial({
    color: 0x9a9184,
    roughness: 0.6,
    metalness: 0.05,
  });
  const glassAmberMaterial = new THREE.MeshStandardMaterial({
    color: 0x8a5a1e,
    roughness: 0.25,
    metalness: 0.1,
    transparent: true,
    opacity: 0.88,
  });
  const danielClothMaterial = new THREE.MeshStandardMaterial({
    map: woolTexture,
    color: new THREE.Color(PALETTE.coalBlueGrey).multiplyScalar(0.8),
    roughness: 0.95,
    metalness: 0,
  });
  const skinMaterial = new THREE.MeshStandardMaterial({
    color: 0x6e5a4c,
    roughness: 0.85,
    metalness: 0,
  });
  const pomegranateMaterial = new THREE.MeshStandardMaterial({
    color: PALETTE.pomegranateRed,
    roughness: 0.5,
    metalness: 0.05,
  });
  const rugMaterial = new THREE.MeshStandardMaterial({
    map: woolTexture,
    color: new THREE.Color(PALETTE.slate).multiplyScalar(0.7),
    roughness: 1,
    metalness: 0,
  });

  const colliders: RoomScene['colliders'] = [];

  // ---- Floor & ceiling ----
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(ROOM_HALF_X * 2, ROOM_HALF_Z * 2), floorMaterial);
  floor.rotation.x = -Math.PI / 2;
  floor.position.y = 0;
  group.add(floor);

  const ceiling = new THREE.Mesh(new THREE.PlaneGeometry(ROOM_HALF_X * 2, ROOM_HALF_Z * 2), wallMaterial);
  ceiling.rotation.x = Math.PI / 2;
  ceiling.position.y = CEILING_Y;
  group.add(ceiling);

  // ---- Walls (north has window opening, south has door opening) ----
  function addWallBox(width: number, height: number, x: number, y: number, z: number) {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(width, height, WALL_T), wallMaterial);
    mesh.position.set(x, y, z);
    group.add(mesh);
  }

  const northZ = NORTH_WALL_Z - WALL_T / 2;
  addWallBox(WINDOW_X_MIN - (-ROOM_HALF_X - WALL_T), CEILING_Y, (-ROOM_HALF_X - WALL_T + WINDOW_X_MIN) / 2, CEILING_Y / 2, northZ);
  addWallBox((ROOM_HALF_X + WALL_T) - WINDOW_X_MAX, CEILING_Y, (WINDOW_X_MAX + ROOM_HALF_X + WALL_T) / 2, CEILING_Y / 2, northZ);
  addWallBox(WINDOW_X_MAX - WINDOW_X_MIN, CEILING_Y - WINDOW_Y_MAX, (WINDOW_X_MIN + WINDOW_X_MAX) / 2, (WINDOW_Y_MAX + CEILING_Y) / 2, northZ);
  addWallBox(WINDOW_X_MAX - WINDOW_X_MIN, WINDOW_Y_MIN, (WINDOW_X_MIN + WINDOW_X_MAX) / 2, WINDOW_Y_MIN / 2, northZ);

  const southZ = SOUTH_WALL_Z + WALL_T / 2;
  addWallBox(DOOR_X_MIN - (-ROOM_HALF_X - WALL_T), CEILING_Y, (-ROOM_HALF_X - WALL_T + DOOR_X_MIN) / 2, CEILING_Y / 2, southZ);
  addWallBox((ROOM_HALF_X + WALL_T) - DOOR_X_MAX, CEILING_Y, (DOOR_X_MAX + ROOM_HALF_X + WALL_T) / 2, CEILING_Y / 2, southZ);
  addWallBox(DOOR_X_MAX - DOOR_X_MIN, CEILING_Y - DOOR_Y_MAX, (DOOR_X_MIN + DOOR_X_MAX) / 2, (DOOR_Y_MAX + CEILING_Y) / 2, southZ);

  const westWall = new THREE.Mesh(new THREE.BoxGeometry(WALL_T, CEILING_Y, ROOM_HALF_Z * 2 + WALL_T * 2), wallMaterial);
  westWall.position.set(-ROOM_HALF_X - WALL_T / 2, CEILING_Y / 2, 0);
  group.add(westWall);

  const eastWall = new THREE.Mesh(new THREE.BoxGeometry(WALL_T, CEILING_Y, ROOM_HALF_Z * 2 + WALL_T * 2), wallMaterial);
  eastWall.position.set(ROOM_HALF_X + WALL_T / 2, CEILING_Y / 2, 0);
  group.add(eastWall);

  colliders.push(
    { minX: -ROOM_HALF_X - WALL_T, maxX: ROOM_HALF_X + WALL_T, minZ: NORTH_WALL_Z - WALL_T, maxZ: NORTH_WALL_Z },
    { minX: -ROOM_HALF_X - WALL_T, maxX: ROOM_HALF_X + WALL_T, minZ: SOUTH_WALL_Z, maxZ: SOUTH_WALL_Z + WALL_T },
    { minX: -ROOM_HALF_X - WALL_T, maxX: -ROOM_HALF_X, minZ: -ROOM_HALF_Z - WALL_T, maxZ: ROOM_HALF_Z + WALL_T },
    { minX: ROOM_HALF_X, maxX: ROOM_HALF_X + WALL_T, minZ: -ROOM_HALF_Z - WALL_T, maxZ: ROOM_HALF_Z + WALL_T },
  );

  // ---- Window assembly ----
  const windowGroup = new THREE.Group();
  const windowCx = (WINDOW_X_MIN + WINDOW_X_MAX) / 2;
  const windowCy = (WINDOW_Y_MIN + WINDOW_Y_MAX) / 2;
  const windowW = WINDOW_X_MAX - WINDOW_X_MIN;
  const windowH = WINDOW_Y_MAX - WINDOW_Y_MIN;

  const frameTrimGeo = new THREE.BoxGeometry(0.06, windowH + 0.1, 0.06);
  const frameLeft = new THREE.Mesh(frameTrimGeo, trimWoodMaterial);
  frameLeft.position.set(WINDOW_X_MIN, windowCy, NORTH_WALL_Z - 0.02);
  windowGroup.add(frameLeft);
  const frameRight = new THREE.Mesh(frameTrimGeo, trimWoodMaterial);
  frameRight.position.set(WINDOW_X_MAX, windowCy, NORTH_WALL_Z - 0.02);
  windowGroup.add(frameRight);
  const frameCross = new THREE.Mesh(new THREE.BoxGeometry(windowW + 0.1, 0.05, 0.05), trimWoodMaterial);
  frameCross.position.set(windowCx, windowCy, NORTH_WALL_Z - 0.02);
  windowGroup.add(frameCross);

  const paneMaterial = new THREE.MeshStandardMaterial({
    color: PALETTE.dirtySnow,
    emissive: PALETTE.coalBlueGrey,
    emissiveIntensity: 0.35,
    map: frostTexture,
    transparent: true,
    opacity: 0.62,
    roughness: 0.85,
    metalness: 0,
    side: THREE.DoubleSide,
  });
  const pane = new THREE.Mesh(new THREE.PlaneGeometry(windowW, windowH), paneMaterial);
  pane.position.set(windowCx, windowCy, NORTH_WALL_Z + 0.01);
  windowGroup.add(pane);

  const curtainMaterial = new THREE.MeshStandardMaterial({
    map: woolTexture,
    color: new THREE.Color(PALETTE.coalBlack).multiplyScalar(1.4),
    roughness: 1,
    metalness: 0,
  });
  const curtain = new THREE.Mesh(new THREE.PlaneGeometry(windowW * 0.32, windowH + 0.06), curtainMaterial);
  curtain.position.set(WINDOW_X_MIN + windowW * 0.15, windowCy, NORTH_WALL_Z + 0.05);
  curtain.rotation.y = 0.12;
  windowGroup.add(curtain);

  const exteriorGround = new THREE.Mesh(
    new THREE.PlaneGeometry(3, 3),
    new THREE.MeshStandardMaterial({ color: new THREE.Color(PALETTE.slate).multiplyScalar(0.25), roughness: 1 }),
  );
  exteriorGround.rotation.x = -Math.PI / 2;
  exteriorGround.position.set(windowCx, 0, NORTH_WALL_Z - 2.2);
  windowGroup.add(exteriorGround);

  const saplingGroup = new THREE.Group();
  const saplingMaterial = new THREE.MeshStandardMaterial({
    color: new THREE.Color(PALETTE.coalBlack).multiplyScalar(1.6),
    roughness: 1,
    metalness: 0,
  });
  const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.03, 0.9, 6), saplingMaterial);
  trunk.position.y = 0.45;
  saplingGroup.add(trunk);
  const canopyPositions: Array<[number, number, number, number]> = [
    [0, 1.15, 0, 0.26],
    [0.14, 1.35, 0.05, 0.19],
    [-0.15, 1.3, -0.06, 0.2],
    [0, 1.5, 0, 0.16],
  ];
  for (const [cx, cy, cz, cr] of canopyPositions) {
    const lump = new THREE.Mesh(new THREE.IcosahedronGeometry(cr, 0), saplingMaterial);
    lump.position.set(cx, cy, cz);
    saplingGroup.add(lump);
  }
  saplingGroup.position.set(windowCx, 0, NORTH_WALL_Z - 1.6);
  windowGroup.add(saplingGroup);

  group.add(windowGroup);

  const snowGeometry = new THREE.BufferGeometry();
  const snowCount = 46;
  const snowPositions = new Float32Array(snowCount * 3);
  const snowSeeds = new Float32Array(snowCount);
  for (let i = 0; i < snowCount; i++) {
    snowPositions[i * 3] = WINDOW_X_MIN + Math.random() * windowW;
    snowPositions[i * 3 + 1] = WINDOW_Y_MIN + Math.random() * windowH;
    snowPositions[i * 3 + 2] = NORTH_WALL_Z - 0.8 - Math.random() * 1.6;
    snowSeeds[i] = Math.random() * 1000;
  }
  snowGeometry.setAttribute('position', new THREE.BufferAttribute(snowPositions, 3));
  const snowMaterial = new THREE.PointsMaterial({
    size: 0.028,
    map: spriteTexture,
    color: PALETTE.dirtySnow,
    transparent: true,
    opacity: 0.75,
    depthWrite: false,
    sizeAttenuation: true,
  });
  const snowPoints = new THREE.Points(snowGeometry, snowMaterial);
  group.add(snowPoints);

  // ---- Door, frame, mezuzah ----
  const doorGroup = new THREE.Group();
  const doorCx = (DOOR_X_MIN + DOOR_X_MAX) / 2;
  const doorW = DOOR_X_MAX - DOOR_X_MIN;
  const doorLeaf = new THREE.Mesh(
    new THREE.BoxGeometry(doorW - 0.06, DOOR_Y_MAX - 0.04, 0.05),
    trimWoodMaterial,
  );
  doorLeaf.position.set(doorCx, (DOOR_Y_MAX - 0.04) / 2, SOUTH_WALL_Z - 0.03);
  doorGroup.add(doorLeaf);

  const doorFrameGeoV = new THREE.BoxGeometry(0.07, DOOR_Y_MAX + 0.08, 0.09);
  const doorFrameLeft = new THREE.Mesh(doorFrameGeoV, trimWoodMaterial);
  doorFrameLeft.position.set(DOOR_X_MIN, DOOR_Y_MAX / 2, SOUTH_WALL_Z - 0.02);
  doorGroup.add(doorFrameLeft);
  const doorFrameRight = new THREE.Mesh(doorFrameGeoV, trimWoodMaterial);
  doorFrameRight.position.set(DOOR_X_MAX, DOOR_Y_MAX / 2, SOUTH_WALL_Z - 0.02);
  doorGroup.add(doorFrameRight);
  const doorFrameTop = new THREE.Mesh(new THREE.BoxGeometry(doorW + 0.14, 0.07, 0.09), trimWoodMaterial);
  doorFrameTop.position.set(doorCx, DOOR_Y_MAX, SOUTH_WALL_Z - 0.02);
  doorGroup.add(doorFrameTop);

  const mezuzahGroup = new THREE.Group();
  const mezuzahCase = new THREE.Mesh(new THREE.BoxGeometry(0.028, 0.13, 0.026), brassMaterial);
  mezuzahGroup.add(mezuzahCase);
  mezuzahGroup.position.set(DOOR_X_MAX + 0.02, 1.4, SOUTH_WALL_Z - 0.05);
  mezuzahGroup.rotation.z = 0.5;
  const mezuzahDefaultPosition = mezuzahGroup.position.clone();
  const mezuzahDefaultRotation = mezuzahGroup.rotation.z;
  doorGroup.add(mezuzahGroup);

  group.add(doorGroup);

  // ---- Table, candle, bowl ----
  const tableGroup = new THREE.Group();
  const tableTop = new THREE.Mesh(new THREE.BoxGeometry(TABLE_SIZE.x, 0.05, TABLE_SIZE.z), trimWoodMaterial);
  tableTop.position.set(TABLE_CENTER.x, TABLE_TOP_Y - 0.025, TABLE_CENTER.z);
  tableGroup.add(tableTop);
  const legGeo = new THREE.CylinderGeometry(0.028, 0.028, TABLE_TOP_Y - 0.05, 8);
  const legOffsets: Array<[number, number]> = [
    [TABLE_SIZE.x / 2 - 0.06, TABLE_SIZE.z / 2 - 0.06],
    [-(TABLE_SIZE.x / 2 - 0.06), TABLE_SIZE.z / 2 - 0.06],
    [TABLE_SIZE.x / 2 - 0.06, -(TABLE_SIZE.z / 2 - 0.06)],
    [-(TABLE_SIZE.x / 2 - 0.06), -(TABLE_SIZE.z / 2 - 0.06)],
  ];
  for (const [ox, oz] of legOffsets) {
    const leg = new THREE.Mesh(legGeo, trimWoodMaterial);
    leg.position.set(TABLE_CENTER.x + ox, (TABLE_TOP_Y - 0.05) / 2, TABLE_CENTER.z + oz);
    tableGroup.add(leg);
  }
  group.add(tableGroup);

  colliders.push({
    minX: TABLE_CENTER.x - TABLE_SIZE.x / 2 - 0.05,
    maxX: TABLE_CENTER.x + TABLE_SIZE.x / 2 + 0.05,
    minZ: TABLE_CENTER.z - TABLE_SIZE.z / 2 - 0.05,
    maxZ: TABLE_CENTER.z + TABLE_SIZE.z / 2 + 0.05,
  });

  const candleGroup = new THREE.Group();
  const candleBase = new THREE.Mesh(new THREE.CylinderGeometry(0.028, 0.032, CANDLE_HEIGHT, 10), waxMaterial);
  candleBase.position.set(CANDLE_POS.x, TABLE_TOP_Y + CANDLE_HEIGHT / 2, CANDLE_POS.z);
  candleGroup.add(candleBase);
  const wick = new THREE.Mesh(new THREE.CylinderGeometry(0.003, 0.003, 0.02, 4), trimWoodMaterial);
  wick.position.set(CANDLE_POS.x, TABLE_TOP_Y + CANDLE_HEIGHT + 0.01, CANDLE_POS.z);
  candleGroup.add(wick);

  const flameMaterial = new THREE.MeshStandardMaterial({
    color: PALETTE.candleAmber,
    emissive: PALETTE.candleHighlight,
    emissiveIntensity: 2.2,
    roughness: 1,
    metalness: 0,
  });
  const flame = new THREE.Mesh(new THREE.SphereGeometry(0.02, 8, 8), flameMaterial);
  flame.scale.set(0.7, 1.5, 0.7);
  const flameBaseY = TABLE_TOP_Y + CANDLE_HEIGHT + 0.03;
  flame.position.set(CANDLE_POS.x, flameBaseY, CANDLE_POS.z);
  candleGroup.add(flame);
  group.add(candleGroup);

  const candleFlameAnchor = new THREE.Object3D();
  candleFlameAnchor.position.set(CANDLE_POS.x, flameBaseY, CANDLE_POS.z);
  group.add(candleFlameAnchor);

  const bowlGroup = new THREE.Group();
  const bowl = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.06, 0.055, 14, 1, true), ceramicMaterial);
  bowl.material.side = THREE.DoubleSide;
  const bowlDefaultPosition = new THREE.Vector3(TABLE_CENTER.x - 0.25, TABLE_TOP_Y + 0.03, TABLE_CENTER.z + 0.15);
  bowl.position.copy(bowlDefaultPosition);
  bowlGroup.add(bowl);
  group.add(bowlGroup);

  // ---- Shelf, honey jar, pomegranate thread ----
  const shelf = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.03, 0.5), trimWoodMaterial);
  shelf.position.set(ROOM_HALF_X - 0.12, 1.05, 0.4);
  group.add(shelf);

  const honeyJarGroup = new THREE.Group();
  const jarBody = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.032, 0.08, 12), glassAmberMaterial);
  jarBody.position.y = 0.04;
  honeyJarGroup.add(jarBody);
  const jarLid = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, 0.012, 12), trimWoodMaterial);
  jarLid.position.y = 0.086;
  honeyJarGroup.add(jarLid);
  const thread = new THREE.Mesh(new THREE.TorusGeometry(0.033, 0.004, 8, 16), pomegranateMaterial);
  thread.rotation.x = Math.PI / 2;
  thread.position.y = 0.065;
  honeyJarGroup.add(thread);
  honeyJarGroup.position.set(ROOM_HALF_X - 0.16, 1.065, 0.4);
  group.add(honeyJarGroup);

  // ---- Wall drawing ----
  const drawingMaterial = new THREE.MeshStandardMaterial({
    map: drawingTexture,
    roughness: 0.9,
    metalness: 0,
    side: THREE.DoubleSide,
  });
  const drawingGroup = new THREE.Group();
  const drawing = new THREE.Mesh(new THREE.PlaneGeometry(0.42, 0.34), drawingMaterial);
  drawingGroup.rotation.y = Math.PI;
  drawingGroup.add(drawing);
  const drawingDefaultPosition = new THREE.Vector3(1.6, 1.35, SOUTH_WALL_Z - 0.03);
  drawingGroup.position.copy(drawingDefaultPosition);
  group.add(drawingGroup);

  // ---- Rug & loose floorboard ----
  // floorboardsAnchor doubles as the interactable's raycast target, so the rug
  // and plank meshes live under it rather than the flat group.
  const floorboardsAnchor = new THREE.Object3D();
  floorboardsAnchor.position.set(RUG_CENTER.x, 0, RUG_CENTER.z);
  group.add(floorboardsAnchor);

  const rug = new THREE.Mesh(new THREE.PlaneGeometry(RUG_SIZE.x, RUG_SIZE.z), rugMaterial);
  rug.rotation.x = -Math.PI / 2;
  rug.position.set(0, 0.004, 0);
  floorboardsAnchor.add(rug);

  const loosePlank = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.03, 0.18), floorMaterial);
  loosePlank.position.set(0, 0.018, 0);
  loosePlank.rotation.z = 0.05;
  floorboardsAnchor.add(loosePlank);

  // ---- Cellar hatch ----
  const hatchGroup = new THREE.Group();
  const hatchPivot = new THREE.Group();
  hatchPivot.position.set(HATCH_CENTER.x - HATCH_SIZE / 2, 0.02, HATCH_CENTER.z);
  const hatchLid = new THREE.Mesh(new THREE.BoxGeometry(HATCH_SIZE, 0.04, HATCH_SIZE), floorMaterial);
  hatchLid.position.set(HATCH_SIZE / 2, 0, 0);
  hatchPivot.add(hatchLid);
  const hatchRing = new THREE.Mesh(new THREE.TorusGeometry(0.05, 0.008, 8, 16), brassMaterial);
  hatchRing.rotation.x = Math.PI / 2;
  hatchRing.position.set(HATCH_SIZE / 2, 0.022, 0);
  hatchPivot.add(hatchRing);
  hatchGroup.add(hatchPivot);
  group.add(hatchGroup);

  const cellarHatchAnchor = new THREE.Object3D();
  cellarHatchAnchor.position.set(HATCH_CENTER.x, 0.05, HATCH_CENTER.z);
  group.add(cellarHatchAnchor);

  let hatchOpenTarget = 0;
  let hatchOpenCurrent = 0;

  // ---- Wardrobe ----
  const wardrobeGroup = new THREE.Group();
  const wardrobeBody = new THREE.Mesh(
    new THREE.BoxGeometry(WARDROBE_SIZE.x, WARDROBE_SIZE.y, WARDROBE_SIZE.z),
    trimWoodMaterial,
  );
  wardrobeBody.position.set(WARDROBE_CENTER.x, WARDROBE_SIZE.y / 2, WARDROBE_CENTER.z);
  wardrobeGroup.add(wardrobeBody);

  const doorFrontX = WARDROBE_CENTER.x + WARDROBE_SIZE.x / 2;
  const doorHalfDepth = WARDROBE_SIZE.z / 2;
  const leftDoorPivot = new THREE.Group();
  leftDoorPivot.position.set(doorFrontX, WARDROBE_SIZE.y / 2, WARDROBE_CENTER.z - doorHalfDepth);
  const leftDoorLeaf = new THREE.Mesh(new THREE.BoxGeometry(0.03, WARDROBE_SIZE.y - 0.06, doorHalfDepth - 0.02), trimWoodMaterial);
  leftDoorLeaf.position.set(-0.015, 0, doorHalfDepth / 2);
  leftDoorPivot.add(leftDoorLeaf);
  wardrobeGroup.add(leftDoorPivot);

  const rightDoorPivot = new THREE.Group();
  rightDoorPivot.position.set(doorFrontX, WARDROBE_SIZE.y / 2, WARDROBE_CENTER.z + doorHalfDepth);
  const rightDoorLeaf = new THREE.Mesh(new THREE.BoxGeometry(0.03, WARDROBE_SIZE.y - 0.06, doorHalfDepth - 0.02), trimWoodMaterial);
  rightDoorLeaf.position.set(-0.015, 0, -doorHalfDepth / 2);
  rightDoorPivot.add(rightDoorLeaf);
  wardrobeGroup.add(rightDoorPivot);

  group.add(wardrobeGroup);

  colliders.push({
    minX: WARDROBE_CENTER.x - WARDROBE_SIZE.x / 2,
    maxX: WARDROBE_CENTER.x + WARDROBE_SIZE.x / 2 + 0.35,
    minZ: WARDROBE_CENTER.z - WARDROBE_SIZE.z / 2,
    maxZ: WARDROBE_CENTER.z + WARDROBE_SIZE.z / 2,
  });

  const wardrobeAnchor = new THREE.Object3D();
  wardrobeAnchor.position.set(WARDROBE_CENTER.x - 0.05, 0, WARDROBE_CENTER.z);
  group.add(wardrobeAnchor);

  let wardrobeDoorTarget = 0;
  let wardrobeDoorCurrent = 0;

  // ---- Daniel ----
  const danielAnchor = new THREE.Object3D();
  danielAnchor.position.copy(DANIEL_DEFAULT_POS);
  group.add(danielAnchor);

  const torso = new THREE.Mesh(new THREE.CylinderGeometry(0.14, 0.18, 0.42, 10), danielClothMaterial);
  torso.position.set(0, 0.26, 0);
  danielAnchor.add(torso);

  const head = new THREE.Mesh(new THREE.SphereGeometry(0.13, 14, 12), skinMaterial);
  head.position.set(0, 0.6, 0);
  danielAnchor.add(head);

  const armGeo = new THREE.CylinderGeometry(0.035, 0.03, 0.28, 8);
  const armLeft = new THREE.Mesh(armGeo, danielClothMaterial);
  armLeft.position.set(-0.16, 0.32, 0.06);
  armLeft.rotation.z = 0.5;
  armLeft.rotation.x = -0.3;
  danielAnchor.add(armLeft);
  const armRight = new THREE.Mesh(armGeo, danielClothMaterial);
  armRight.position.set(0.16, 0.32, 0.06);
  armRight.rotation.z = -0.5;
  armRight.rotation.x = -0.3;
  danielAnchor.add(armRight);

  const legGeoDaniel = new THREE.BoxGeometry(0.13, 0.07, 0.32);
  const legLeft = new THREE.Mesh(legGeoDaniel, danielClothMaterial);
  legLeft.position.set(-0.08, 0.07, 0.18);
  danielAnchor.add(legLeft);
  const legRight = new THREE.Mesh(legGeoDaniel, danielClothMaterial);
  legRight.position.set(0.08, 0.07, 0.18);
  danielAnchor.add(legRight);

  // ---- Dust motes near candle ----
  const dustCount = 42;
  const dustGeometry = new THREE.BufferGeometry();
  const dustPositions = new Float32Array(dustCount * 3);
  const dustSeeds = new Float32Array(dustCount * 2);
  for (let i = 0; i < dustCount; i++) {
    const angle = Math.random() * Math.PI * 2;
    const radius = 0.15 + Math.random() * 0.55;
    dustPositions[i * 3] = CANDLE_POS.x + Math.cos(angle) * radius;
    dustPositions[i * 3 + 1] = 0.6 + Math.random() * 0.9;
    dustPositions[i * 3 + 2] = CANDLE_POS.z + Math.sin(angle) * radius;
    dustSeeds[i * 2] = Math.random() * 1000;
    dustSeeds[i * 2 + 1] = 0.3 + Math.random() * 0.7;
  }
  dustGeometry.setAttribute('position', new THREE.BufferAttribute(dustPositions, 3));
  const dustMaterial = new THREE.PointsMaterial({
    size: 0.016,
    map: spriteTexture,
    color: PALETTE.candleAmber,
    transparent: true,
    opacity: 0.55,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    sizeAttenuation: true,
  });
  const dustPoints = new THREE.Points(dustGeometry, dustMaterial);
  group.add(dustPoints);

  function setEvidenceHidden(id: EvidenceItemId, hidden: boolean): void {
    if (id === 'tableBowl') {
      bowlGroup.visible = !hidden;
    } else if (id === 'wallDrawing') {
      drawingGroup.visible = !hidden;
    } else if (id === 'doorframeMezuzah') {
      if (hidden) {
        mezuzahGroup.position.set(DOOR_X_MAX + 0.02, 0.08, SOUTH_WALL_Z - 0.02);
        mezuzahGroup.rotation.z = Math.PI / 2;
      } else {
        mezuzahGroup.position.copy(mezuzahDefaultPosition);
        mezuzahGroup.rotation.z = mezuzahDefaultRotation;
      }
    }
  }

  // ---- Daniel visibility / hiding-spot staging ----
  const hidingAnchors: Record<HidingSpotId, THREE.Object3D> = {
    hidingWardrobe: wardrobeAnchor,
    hidingFloorboards: floorboardsAnchor,
    hidingCellarHatch: cellarHatchAnchor,
  };

  function getHidingSpotAnchor(id: HidingSpotId): THREE.Object3D {
    return hidingAnchors[id];
  }

  function setDanielVisible(visible: boolean, atSpot?: HidingSpotId): void {
    wardrobeDoorTarget = 0;
    hatchOpenTarget = 0;
    danielAnchor.scale.set(1, 1, 1);
    danielAnchor.visible = visible;

    if (!atSpot) {
      danielAnchor.position.copy(DANIEL_DEFAULT_POS);
      danielAnchor.rotation.y = 0;
      return;
    }

    if (atSpot === 'hidingWardrobe') {
      const anchor = getHidingSpotAnchor(atSpot);
      danielAnchor.position.set(anchor.position.x + 0.05, 0, anchor.position.z + 0.05);
      danielAnchor.rotation.y = Math.PI * 0.15;
      danielAnchor.scale.set(0.92, 0.92, 0.92);
      wardrobeDoorTarget = 1;
    } else if (atSpot === 'hidingFloorboards') {
      const anchor = getHidingSpotAnchor(atSpot);
      danielAnchor.position.set(anchor.position.x, 0, anchor.position.z);
      danielAnchor.rotation.y = Math.PI * 0.4;
      danielAnchor.scale.set(0.55, 0.4, 0.55);
    } else if (atSpot === 'hidingCellarHatch') {
      danielAnchor.visible = false;
      hatchOpenTarget = 1;
    }
  }

  // ---- Interactables ----
  const interactables: InteractableDef[] = [
    {
      id: 'candle',
      object: candleGroup,
      isAvailable: (beat: StoryBeat) => beat === 'quiet',
      getPromptLabel: () => 'The candle. Your only light.',
    },
    {
      id: 'honeyJar',
      object: honeyJarGroup,
      isAvailable: (beat: StoryBeat) => beat === 'quiet' || beat === 'cough',
      getPromptLabel: (beat: StoryBeat) => (beat === 'cough' ? 'Give Daniel the honey' : 'The last of the honey'),
    },
    {
      id: 'daniel',
      object: danielAnchor,
      isAvailable: (beat: StoryBeat) => beat === 'quiet' || beat === 'cough',
      getPromptLabel: (beat: StoryBeat) => (beat === 'cough' ? 'Go to him — cover his mouth' : 'Go to Daniel'),
    },
    {
      id: 'hidingWardrobe',
      object: wardrobeGroup,
      isAvailable: (beat: StoryBeat, state: ExposureState) =>
        beat === 'hideChild' || (beat === 'cough' && state.hidingSpot === 'hidingWardrobe'),
      getPromptLabel: (beat: StoryBeat) =>
        beat === 'hideChild' ? 'Hide him in the wardrobe — together' : 'Tuck him deeper into the blankets',
    },
    {
      id: 'hidingFloorboards',
      object: floorboardsAnchor,
      isAvailable: (beat: StoryBeat, state: ExposureState) =>
        beat === 'hideChild' || (beat === 'cough' && state.hidingSpot === 'hidingFloorboards'),
      getPromptLabel: (beat: StoryBeat) =>
        beat === 'hideChild' ? 'Hide him beneath the floorboards — alone, but well hidden' : 'Tuck him deeper into the blankets',
    },
    {
      id: 'hidingCellarHatch',
      object: hatchGroup,
      isAvailable: (beat: StoryBeat, state: ExposureState) =>
        beat === 'hideChild' || (beat === 'cough' && state.hidingSpot === 'hidingCellarHatch'),
      getPromptLabel: (beat: StoryBeat) =>
        beat === 'hideChild' ? 'Send him down to the cellar hatch — farthest, safest' : 'Tuck him deeper into the blankets',
    },
    {
      id: 'tableBowl',
      object: bowlGroup,
      isAvailable: (beat: StoryBeat) => beat === 'roomEvidence',
      getPromptLabel: (_beat: StoryBeat, state: ExposureState) =>
        state.hiddenEvidence.includes('tableBowl') ? 'Bring the second bowl back out' : 'Hide the second bowl',
    },
    {
      id: 'wallDrawing',
      object: drawingGroup,
      isAvailable: (beat: StoryBeat) => beat === 'roomEvidence',
      getPromptLabel: (_beat: StoryBeat, state: ExposureState) =>
        state.hiddenEvidence.includes('wallDrawing') ? 'Put the drawing back on the wall' : 'Take down the drawing',
    },
    {
      id: 'doorframeMezuzah',
      object: mezuzahGroup,
      isAvailable: (beat: StoryBeat) => beat === 'roomEvidence',
      getPromptLabel: (_beat: StoryBeat, state: ExposureState) =>
        state.hiddenEvidence.includes('doorframeMezuzah') ? 'Fix the mezuzah back to the frame' : 'Take down the mezuzah',
    },
    {
      id: 'door',
      object: doorLeaf,
      isAvailable: (beat: StoryBeat) => beat === 'knock',
      getPromptLabel: () => 'Open the door',
    },
  ];

  // ---- Spawn ----
  const playerSpawn = new THREE.Vector3(0, 1.6, 1.3);
  const spawnDx = DANIEL_DEFAULT_POS.x - playerSpawn.x;
  const spawnDz = DANIEL_DEFAULT_POS.z - playerSpawn.z;
  const playerSpawnYaw = Math.atan2(-spawnDx, -spawnDz);

  // ---- Update loop ----
  const dustBase = dustPositions.slice();
  const snowBase = snowPositions.slice();

  function update(dt: number, elapsed: number): void {
    const flicker = fractalNoise1D(elapsed * 6.0, 3);
    const flickerFast = fractalNoise1D(elapsed * 17.0 + 40, 2);
    flame.scale.set(0.65 + flicker * 0.15, 1.4 + flicker * 0.3 + flickerFast * 0.1, 0.65 + flicker * 0.15);
    flame.position.y = flameBaseY + flickerFast * 0.006;
    flameMaterial.emissiveIntensity = 1.9 + flicker * 0.6;

    const dustPos = dustGeometry.getAttribute('position') as THREE.BufferAttribute;
    for (let i = 0; i < dustCount; i++) {
      const seed = dustSeeds[i * 2];
      const speed = dustSeeds[i * 2 + 1];
      const bx = dustBase[i * 3];
      const by = dustBase[i * 3 + 1];
      const bz = dustBase[i * 3 + 2];
      const swirl = fractalNoise1D(elapsed * 0.15 * speed + seed, 2) - 0.5;
      const drift = fractalNoise1D(elapsed * 0.1 * speed + seed + 90, 2) - 0.5;
      dustPos.setXYZ(
        i,
        bx + swirl * 0.25,
        by + Math.sin(elapsed * 0.3 * speed + seed) * 0.12,
        bz + drift * 0.25,
      );
    }
    dustPos.needsUpdate = true;

    const snowPos = snowGeometry.getAttribute('position') as THREE.BufferAttribute;
    for (let i = 0; i < snowCount; i++) {
      const seed = snowSeeds[i];
      const fallSpeed = 0.05 + (seed % 10) * 0.004;
      let y = snowPos.getY(i) - fallSpeed * dt;
      if (y < WINDOW_Y_MIN) y = WINDOW_Y_MAX;
      const driftX = Math.sin(elapsed * 0.4 + seed) * 0.0015;
      const bx = snowBase[i * 3];
      const x = clamp(snowPos.getX(i) + driftX, WINDOW_X_MIN, WINDOW_X_MAX);
      const z = snowBase[i * 3 + 2];
      snowPos.setXYZ(i, Math.abs(x - bx) > windowW ? bx : x, y, z);
    }
    snowPos.needsUpdate = true;

    const doorLerpT = clamp(dt * 3, 0, 1);
    wardrobeDoorCurrent = lerp(wardrobeDoorCurrent, wardrobeDoorTarget, doorLerpT);
    leftDoorPivot.rotation.y = -wardrobeDoorCurrent * 1.9;
    rightDoorPivot.rotation.y = wardrobeDoorCurrent * 1.9;

    hatchOpenCurrent = lerp(hatchOpenCurrent, hatchOpenTarget, doorLerpT);
    hatchPivot.rotation.z = hatchOpenCurrent * 1.3;
  }

  return {
    group,
    interactables,
    candleFlameAnchor,
    danielAnchor,
    getHidingSpotAnchor,
    setDanielVisible,
    setEvidenceHidden,
    playerSpawn,
    playerSpawnYaw,
    colliders,
    update,
  };
}
