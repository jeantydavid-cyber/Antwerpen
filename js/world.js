import * as THREE from 'three';

const STONE = 0x8d8478;
const STONE_DARK = 0x5c554c;
const ROOF_RED = 0x7a3b2e;
const GOLD_TRIM = 0xb08d57;
const WINDOW_GLOW = 0xffd98a;

function makeGuildHouse(scene, colliders, { x, z, width, depth, height, roofColor, rotationY = 0 }) {
  const group = new THREE.Group();

  const body = new THREE.Mesh(
    new THREE.BoxGeometry(width, height, depth),
    new THREE.MeshStandardMaterial({ color: STONE, roughness: 0.9 })
  );
  body.position.y = height / 2;
  body.castShadow = true;
  body.receiveShadow = true;
  group.add(body);

  const stepHeight = height * 0.28;
  const stepGeo = new THREE.BoxGeometry(width * 0.7, stepHeight, depth * 0.4);
  const stepMat = new THREE.MeshStandardMaterial({ color: roofColor, roughness: 0.8 });
  const gable = new THREE.Mesh(stepGeo, stepMat);
  gable.position.set(0, height + stepHeight / 2, 0);
  group.add(gable);

  const topGeo = new THREE.ConeGeometry(width * 0.32, height * 0.35, 4);
  const top = new THREE.Mesh(topGeo, stepMat);
  top.rotation.y = Math.PI / 4;
  top.position.set(0, height + stepHeight + (height * 0.35) / 2, 0);
  group.add(top);

  const rows = Math.max(1, Math.floor(height / 2.2));
  const cols = Math.max(1, Math.floor(width / 2));
  const winGeo = new THREE.PlaneGeometry(0.6, 0.9);
  const winMat = new THREE.MeshStandardMaterial({
    color: WINDOW_GLOW,
    emissive: WINDOW_GLOW,
    emissiveIntensity: 0.6,
  });
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const win = new THREE.Mesh(winGeo, winMat);
      const wx = -width / 2 + (c + 0.5) * (width / cols);
      const wy = 1.2 + r * 2.1;
      if (wy > height - 0.4) continue;
      win.position.set(wx, wy, depth / 2 + 0.01);
      group.add(win);
    }
  }

  group.position.set(x, 0, z);
  group.rotation.y = rotationY;
  scene.add(group);

  colliders.push({
    minX: x - width / 2 - 0.4,
    maxX: x + width / 2 + 0.4,
    minZ: z - depth / 2 - 0.4,
    maxZ: z + depth / 2 + 0.4,
  });

  return group;
}

function makeCathedralSpire(scene, colliders, x, z) {
  const group = new THREE.Group();
  const baseMat = new THREE.MeshStandardMaterial({ color: STONE_DARK, roughness: 0.85 });

  const base = new THREE.Mesh(new THREE.BoxGeometry(9, 14, 9), baseMat);
  base.position.y = 7;
  group.add(base);

  const towerTop = new THREE.Mesh(new THREE.BoxGeometry(6, 6, 6), baseMat);
  towerTop.position.y = 14 + 3;
  group.add(towerTop);

  const spire = new THREE.Mesh(new THREE.ConeGeometry(4.2, 16, 8), baseMat);
  spire.position.y = 14 + 6 + 8;
  group.add(spire);

  for (const [dx, dz] of [[-3.2, -3.2], [3.2, -3.2], [-3.2, 3.2], [3.2, 3.2]]) {
    const spike = new THREE.Mesh(new THREE.ConeGeometry(0.8, 3, 6), baseMat);
    spike.position.set(dx, 14 + 3 + 1.5, dz);
    group.add(spike);
  }

  group.position.set(x, 0, z);
  scene.add(group);

  colliders.push({ minX: x - 5, maxX: x + 5, minZ: z - 5, maxZ: z + 5 });
  return group;
}

function makeFountain(scene, colliders, x, z) {
  const group = new THREE.Group();
  const stoneMat = new THREE.MeshStandardMaterial({ color: STONE, roughness: 0.8 });

  const basin = new THREE.Mesh(new THREE.CylinderGeometry(3, 3.3, 0.8, 24), stoneMat);
  basin.position.y = 0.4;
  group.add(basin);

  const pedestal = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.6, 3, 12), stoneMat);
  pedestal.position.y = 0.8 + 1.5;
  group.add(pedestal);

  const figure = new THREE.Mesh(
    new THREE.ConeGeometry(0.7, 2, 8),
    new THREE.MeshStandardMaterial({ color: GOLD_TRIM, metalness: 0.4, roughness: 0.4 })
  );
  figure.position.y = 0.8 + 3 + 1;
  group.add(figure);

  const water = new THREE.Mesh(
    new THREE.CylinderGeometry(2.8, 2.8, 0.05, 24),
    new THREE.MeshStandardMaterial({ color: 0x2b4a5a, roughness: 0.2, metalness: 0.3 })
  );
  water.position.y = 0.82;
  group.add(water);

  group.position.set(x, 0, z);
  scene.add(group);

  colliders.push({ minX: x - 3.3, maxX: x + 3.3, minZ: z - 3.3, maxZ: z + 3.3 });
  return group;
}

function makeLamp(scene, x, z) {
  const post = new THREE.Mesh(
    new THREE.CylinderGeometry(0.08, 0.1, 3.2, 8),
    new THREE.MeshStandardMaterial({ color: 0x1c1c1c, roughness: 0.6, metalness: 0.5 })
  );
  post.position.set(x, 1.6, z);
  scene.add(post);

  const bulb = new THREE.Mesh(
    new THREE.SphereGeometry(0.18, 12, 12),
    new THREE.MeshStandardMaterial({ color: WINDOW_GLOW, emissive: WINDOW_GLOW, emissiveIntensity: 1.2 })
  );
  bulb.position.set(x, 3.25, z);
  scene.add(bulb);

  const light = new THREE.PointLight(0xffd98a, 6, 14, 2);
  light.position.set(x, 3.2, z);
  scene.add(light);
}

export function createWorld(scene) {
  const colliders = [];

  scene.fog = new THREE.FogExp2(0x0a0a12, 0.018);
  scene.background = new THREE.Color(0x0a0a12);

  const ambient = new THREE.AmbientLight(0x33344a, 1.2);
  scene.add(ambient);

  const moon = new THREE.DirectionalLight(0x8fa6d9, 0.5);
  moon.position.set(-30, 40, -20);
  scene.add(moon);

  const groundGeo = new THREE.PlaneGeometry(140, 140, 1, 1);
  const groundMat = new THREE.MeshStandardMaterial({ color: 0x3a352e, roughness: 1 });
  const ground = new THREE.Mesh(groundGeo, groundMat);
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  scene.add(ground);

  const plazaMat = new THREE.MeshStandardMaterial({ color: 0x54503f, roughness: 1 });
  const plaza = new THREE.Mesh(new THREE.CircleGeometry(26, 32), plazaMat);
  plaza.rotation.x = -Math.PI / 2;
  plaza.position.y = 0.01;
  scene.add(plaza);

  // Guild houses ringing the Grote Markt
  const houses = [
    { x: -18, z: -22, width: 6, depth: 6, height: 8, roofColor: ROOF_RED, rotationY: 0 },
    { x: -10, z: -24, width: 5, depth: 6, height: 9, roofColor: 0x3b5c46, rotationY: 0 },
    { x: -2, z: -25, width: 6, depth: 6, height: 7.5, roofColor: ROOF_RED, rotationY: 0 },
    { x: 16, z: -23, width: 6, depth: 6, height: 8.5, roofColor: 0x3b5c46, rotationY: 0 },
    { x: 22, z: -18, width: 5, depth: 6, height: 7, roofColor: ROOF_RED, rotationY: 0 },
    { x: 24, z: 6, width: 6, depth: 6, height: 8, roofColor: 0x3b5c46, rotationY: Math.PI / 2 },
    { x: 22, z: 18, width: 5, depth: 6, height: 9, roofColor: ROOF_RED, rotationY: Math.PI / 2 },
    { x: -22, z: 8, width: 6, depth: 6, height: 8, roofColor: ROOF_RED, rotationY: -Math.PI / 2 },
    { x: -24, z: 18, width: 5, depth: 6, height: 7.5, roofColor: 0x3b5c46, rotationY: -Math.PI / 2 },
  ];
  for (const h of houses) makeGuildHouse(scene, colliders, h);

  makeCathedralSpire(scene, colliders, 4, 24);
  makeFountain(scene, colliders, 0, 0);

  const lampPositions = [
    [-14, -10], [14, -10], [-14, 12], [14, 12], [0, -14], [0, 16],
  ];
  for (const [x, z] of lampPositions) makeLamp(scene, x, z);

  // Boundary walls (invisible) so the player can't walk off into the void
  const boundary = 34;
  colliders.push(
    { minX: -boundary - 1, maxX: -boundary, minZ: -boundary, maxZ: boundary },
    { minX: boundary, maxX: boundary + 1, minZ: -boundary, maxZ: boundary },
    { minX: -boundary, maxX: boundary, minZ: -boundary - 1, maxZ: -boundary },
    { minX: -boundary, maxX: boundary, minZ: boundary, maxZ: boundary + 1 }
  );

  return { colliders };
}

export function createDiamonds(scene) {
  const positions = [
    new THREE.Vector3(-16, 1.1, -12),
    new THREE.Vector3(18, 1.1, 10),
    new THREE.Vector3(2, 1.1, 20),
  ];

  const geo = new THREE.OctahedronGeometry(0.35, 0);
  const mat = new THREE.MeshStandardMaterial({
    color: 0x8fe3ff,
    emissive: 0x2fb6d9,
    emissiveIntensity: 0.8,
    metalness: 0.6,
    roughness: 0.1,
  });

  const diamonds = positions.map((pos) => {
    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.copy(pos);
    const light = new THREE.PointLight(0x8fe3ff, 2, 4, 2);
    light.position.set(0, 0.2, 0);
    mesh.add(light);
    scene.add(mesh);
    return mesh;
  });

  return diamonds;
}
