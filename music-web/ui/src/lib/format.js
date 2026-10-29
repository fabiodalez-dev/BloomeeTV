export function time(s) {
  if (!isFinite(s) || s < 0) s = 0;
  s = Math.floor(s);
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = String(s % 60).padStart(2, "0");
  return h ? h + ":" + String(m).padStart(2, "0") + ":" + x : m + ":" + x;
}

export function minutes(n) {
  if (n < 60) return n + " min";
  const h = Math.floor(n / 60);
  return h + " h " + (n % 60 ? (n % 60) + " min" : "");
}

export function ago(ts) {
  const d = Date.now() / 1000 - ts;
  if (d < 60) return "adesso";
  if (d < 3600) return Math.floor(d / 60) + " min fa";
  if (d < 86400) return Math.floor(d / 3600) + " h fa";
  if (d < 86400 * 7) return Math.floor(d / 86400) + " g fa";
  return new Date(ts * 1000).toLocaleDateString("it-IT", { day: "numeric", month: "short" });
}

// Copertina alla misura richiesta. Il server immagini di Google risponde solo
// a certe misure, diverse da immagine a immagine (96 o 320 a volte danno
// errore): si sale alla prima misura che finora ha sempre funzionato.
const SIZES = [60, 120, 160, 226, 544, 720, 1200];
export function snap(size) {
  return SIZES.find((s) => s >= size) || 1200;
}

// Le copertine di Google si chiedono in WebP a qualità 75: a 544 px pesano
// circa 22 KB invece dei 56 KB del JPEG a qualità 90 (e dei 150+ KB senza
// parametri). Altri indirizzi (miniature video, mixart) restano come sono.
export function sized(url, size) {
  if (!url) return null;
  size = snap(size);
  if (/^https:\/\/[a-z0-9.-]*(googleusercontent|ggpht)\.com\/[^=]+=/.test(url)) {
    return url.replace(/=[^=/]*$/, "=w" + size + "-h" + size + "-l75-rw");
  }
  // Miniature dei video: 320×180 (circa 15 KB) o 480×360 al posto di quelle grandi.
  const video = url.match(/^https:\/\/i\.ytimg\.com\/vi(?:_webp)?\/([\w-]{11})\//);
  if (video) return "https://i.ytimg.com/vi/" + video[1] + (size <= 320 ? "/mqdefault.jpg" : "/hqdefault.jpg");
  return url;
}

// Forma "biscotto" di Material 3 Expressive: cerchio con lobi morbidi.
export function cookiePath(lobes = 9, depth = 0.06, steps = 360) {
  let d = "";
  for (let i = 0; i <= steps; i++) {
    const a = (i / steps) * Math.PI * 2;
    const r = 0.5 - depth + depth * Math.cos(lobes * a);
    const x = 0.5 + r * Math.cos(a - Math.PI / 2), y = 0.5 + r * Math.sin(a - Math.PI / 2);
    d += (i ? "L" : "M") + x.toFixed(4) + " " + y.toFixed(4);
  }
  return d + "Z";
}
