// Stato condiviso dell'app: sessione, libreria, impostazioni, avvisi, percorso.
import { get, post, put, del, setUnauthorizedHandler } from "./api.js";

export const session = $state({ loading: true, user: null, youtube: null, youtubeCode: false, setup: false });

export const DEFAULT_SETTINGS = {
  theme: "auto", // auto | dark | light
  dynamicColor: true,
  autoplay: true,
  crossfade: 0,
  eq: { enabled: false, preset: "flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], preamp: 0 },
  rotateCover: true,
  onboarded: false,
  quality: "auto" // auto | aac
};
export const settings = $state(structuredClone(DEFAULT_SETTINGS));

export const library = $state({ loaded: false, favorites: [], playlists: [], home: {} });

// Avvisi in basso: un messaggio alla volta, con azione facoltativa.
export const toasts = $state({ items: [] });
let toastId = 0;
export function toast(message, action) {
  const id = ++toastId;
  toasts.items = [...toasts.items.slice(-2), { id, message, action }];
  setTimeout(() => dismiss(id), action ? 6000 : 3500);
}
export function dismiss(id) {
  toasts.items = toasts.items.filter((t) => t.id !== id);
}

// Percorso: History API, con le stesse URL che il server rimanda a index.html.
export const route = $state({ path: location.pathname, query: Object.fromEntries(new URLSearchParams(location.search)) });
export function navigate(to, { replace = false } = {}) {
  const url = new URL(to, location.origin);
  if (url.pathname + url.search === location.pathname + location.search) return;
  history[replace ? "replaceState" : "pushState"]({}, "", url.pathname + url.search);
  route.path = url.pathname;
  route.query = Object.fromEntries(url.searchParams);
  document.getElementById("main")?.scrollTo({ top: 0 });
  window.scrollTo({ top: 0 });
}
window.addEventListener("popstate", () => {
  route.path = location.pathname;
  route.query = Object.fromEntries(new URLSearchParams(location.search));
});

// Collegamenti per i vari tipi di elemento YouTube.
export function hrefOf(it) {
  if (!it) return null;
  if (it.kind === "artist" || (it.browseId || "").startsWith("UC")) return "/artist/" + it.browseId;
  if (it.kind === "album" || (it.browseId || "").startsWith("MPREb")) return "/album/" + it.browseId;
  if (it.kind === "playlist" || /^(VL|PL|RD|OLAK)/.test(it.browseId || "")) return "/playlist/" + it.browseId;
  if (it.browseId) return "/browse/" + it.browseId + (it.params ? "?params=" + encodeURIComponent(it.params) : "");
  return null;
}

// Sessione

setUnauthorizedHandler(() => {
  if (session.user) {
    session.user = null;
    toast("Sessione scaduta: accedi di nuovo");
  }
});

export async function loadSession() {
  session.loading = true;
  try {
    const d = await get("/api/session", { quiet401: true });
    session.user = d.user;
    session.youtube = d.youtube;
    session.youtubeCode = !!d.youtubeCode;
    await loadLibrary();
  } catch (e) {
    session.user = null;
    session.setup = !!(e.data && e.data.setup);
  } finally {
    session.loading = false;
  }
}

export async function logout() {
  try {
    await post("/api/logout");
  } catch {}
  session.user = null;
  library.loaded = false;
  navigate("/", { replace: true });
}

// Libreria

export async function loadLibrary() {
  const d = await get("/api/library");
  library.favorites = d.favorites;
  library.playlists = d.playlists;
  library.home = d.home || {};
  Object.assign(settings, structuredClone(DEFAULT_SETTINGS), d.settings || {});
  library.loaded = true;
}

export function keyOf(it) {
  return it.kind === "song" ? it.videoId : it.browseId;
}

export function isFavorite(it) {
  const k = it && keyOf(it);
  return !!k && library.favorites.some((f) => keyOf(f) === k);
}

export async function toggleFavorite(it) {
  const k = keyOf(it);
  if (isFavorite(it)) {
    const before = library.favorites;
    library.favorites = before.filter((f) => keyOf(f) !== k);
    try {
      await del("/api/favorites/" + encodeURIComponent(k));
      toast("Rimosso dai preferiti");
    } catch (e) {
      library.favorites = before;
      toast(e.message);
    }
  } else {
    try {
      const d = await put("/api/favorites", { item: it });
      library.favorites = [{ ...d.item, addedAt: Date.now() / 1000 }, ...library.favorites];
      toast("Aggiunto ai preferiti");
    } catch (e) {
      toast(e.message);
    }
  }
}

export async function refreshPlaylists() {
  library.playlists = (await get("/api/playlists")).playlists;
}

let settingsTimer;
export function saveSettings() {
  clearTimeout(settingsTimer);
  settingsTimer = setTimeout(() => {
    put("/api/state/settings", { data: $state.snapshot(settings) }).catch((e) => toast(e.message));
  }, 600);
}

export function saveHome() {
  put("/api/state/home", { data: $state.snapshot(library.home) }).catch((e) => toast(e.message));
}

// Menu contestuale e finestre condivise.
export const ui = $state({
  menu: null, // { item, x, y, context }
  addTo: null, // brani da aggiungere a una playlist
  nowPlaying: false, // lettore a schermo intero
  panel: "lyrics", // pannello del lettore: lyrics | queue
  side: null // pannello laterale su desktop: queue | lyrics | null
});
