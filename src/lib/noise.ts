function hash(n: number): number {
  const s = Math.sin(n) * 43758.5453123;
  return s - Math.floor(s);
}

function valueNoise1D(x: number): number {
  const i = Math.floor(x);
  const f = x - i;
  const a = hash(i);
  const b = hash(i + 1);
  const t = f * f * (3 - 2 * f);
  return a + (b - a) * t;
}

export function fractalNoise1D(x: number, octaves = 4): number {
  let total = 0;
  let amplitude = 1;
  let frequency = 1;
  let maxAmplitude = 0;
  for (let i = 0; i < octaves; i++) {
    total += valueNoise1D(x * frequency) * amplitude;
    maxAmplitude += amplitude;
    amplitude *= 0.5;
    frequency *= 2;
  }
  return total / maxAmplitude;
}
