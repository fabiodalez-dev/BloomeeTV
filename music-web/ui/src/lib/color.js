// Colore dalla copertina, come il tema dinamico di Mochy: tinta e croma in
// OKLCH di un colore vivace e rappresentativo; tutta la palette (scura e
// chiara) si ricava in CSS da --seed-h e --seed-c.

export const DEFAULT_SEED = { h: 145, c: 0.085 };
const cache = new Map();

function srgbToLinear(v) {
  v /= 255;
  return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}

export function toOklch(r, g, b) {
  const R = srgbToLinear(r), G = srgbToLinear(g), B = srgbToLinear(b);
  const l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B);
  const m = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B);
  const s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B);
  const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
  const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  const Bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  const C = Math.hypot(A, Bb);
  let H = (Math.atan2(Bb, A) * 180) / Math.PI;
  if (H < 0) H += 360;
  return { l: L, c: C, h: H };
}

// Istogramma per tinta pesato per croma e per quanto il colore non sia né
// troppo scuro né troppo chiaro: vince la tinta che "si vede" di più.
export function seedFromPixels(data) {
  const bins = new Array(36).fill(0);
  const chroma = new Array(36).fill(0);
  let total = 0;
  for (let i = 0; i < data.length; i += 4) {
    if (data[i + 3] < 128) continue;
    const { l, c, h } = toOklch(data[i], data[i + 1], data[i + 2]);
    if (c < 0.03 || l < 0.18 || l > 0.95) continue;
    const w = c * (1 - Math.abs(l - 0.6));
    const k = Math.floor(h / 10) % 36;
    bins[k] += w;
    chroma[k] += c * w;
    total += w;
  }
  if (total < 0.5) return null;
  let best = 0;
  for (let k = 0; k < 36; k++) {
    const score = bins[(k + 35) % 36] * 0.5 + bins[k] + bins[(k + 1) % 36] * 0.5;
    const bestScore = bins[(best + 35) % 36] * 0.5 + bins[best] + bins[(best + 1) % 36] * 0.5;
    if (score > bestScore) best = k;
  }
  const c = chroma[best] / bins[best];
  return { h: best * 10 + 5, c: Math.max(0.04, Math.min(0.16, c)) };
}

export function seedFromImage(url, retry = true) {
  if (!url) return Promise.resolve(null);
  // Dal server (stessa origine): Google risponde 429 alle richieste CORS.
  const small = "/api/thumb?url=" + encodeURIComponent(url);
  if (cache.has(small)) return Promise.resolve(cache.get(small));
  return new Promise((resolve) => {
    const img = new Image();
    img.decoding = "async";
    img.onload = () => {
      try {
        const canvas = document.createElement("canvas");
        canvas.width = canvas.height = 40;
        const ctx = canvas.getContext("2d", { willReadFrequently: true });
        ctx.drawImage(img, 0, 0, 40, 40);
        const seed = seedFromPixels(ctx.getImageData(0, 0, 40, 40).data);
        cache.set(small, seed);
        resolve(seed);
      } catch {
        resolve(null);
      }
    };
    // Google a volte risponde 429: un secondo tentativo poco dopo.
    img.onerror = () => (retry ? setTimeout(() => seedFromImage(url, false).then(resolve), 1500) : resolve(null));
    img.src = small;
  });
}

export function applySeed(seed, el = document.documentElement) {
  const s = seed || DEFAULT_SEED;
  el.style.setProperty("--seed-h", s.h.toFixed(1));
  el.style.setProperty("--seed-c", s.c.toFixed(3));
}
