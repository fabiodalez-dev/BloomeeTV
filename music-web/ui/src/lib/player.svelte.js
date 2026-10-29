// Lettore: coda, riproduzione, crossfade, equalizzatore, Media Session,
// cronologia, riproduzione automatica (radio) e timer di spegnimento.
//
// L'audio arriva da /api/audio/<id> a pezzi Range: l'elemento <audio> li
// chiede da solo. Due elementi si alternano per sfumare un brano nel successivo.
import { yt, get, post, put } from "./api.js";
import * as Y from "./yt.js";
import { settings, toast } from "./state.svelte.js";
import { sized } from "./format.js";

const OPUS = typeof Audio !== "undefined" && new Audio().canPlayType('audio/webm; codecs="opus"') !== "";
export const EQ_FREQS = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
export const EQ_PRESETS = {
  flat: ["Piatto", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]],
  bass: ["Bassi", [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]],
  treble: ["Alti", [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]],
  vocal: ["Voce", [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]],
  loudness: ["Loudness", [5, 4, 2, 0, -1, 0, -1, 1, 4, 5]],
  acoustic: ["Acustico", [3, 3, 2, 1, 1, 1, 2, 2, 2, 1]],
  electronic: ["Elettronica", [5, 4, 1, 0, -2, 1, 0, 1, 4, 5]],
  rock: ["Rock", [4, 3, 2, 1, -1, -1, 1, 2, 3, 4]],
  pop: ["Pop", [-1, 0, 2, 3, 4, 3, 1, 0, -1, -1]],
  classical: ["Classica", [4, 3, 2, 1, 0, 0, 0, 1, 2, 3]]
};

function audioUrl(videoId, alt) {
  return "/api/audio/" + videoId + (alt ? "?alt=1" : "");
}

function shuffled(list) {
  const a = list.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

const songOnly = (items) => items.filter((i) => i && i.videoId).map((i) => ({ ...i, kind: "song" }));

class Player {
  queue = $state([]);
  index = $state(-1);
  playing = $state(false);
  loading = $state(false);
  time = $state(0);
  duration = $state(0);
  buffered = $state(0);
  shuffle = $state(false);
  repeat = $state("off"); // off | all | one
  volume = $state(1);
  muted = $state(false);
  sleep = $state(null); // { until } | { track: true }
  error = $state(null);
  current = $derived(this.queue[this.index] || null);
  hasNext = $derived(this.index + 1 < this.queue.length || this.repeat === "all");

  els = [];
  active = 0;
  alt = !OPUS;
  failures = 0;
  fading = null;
  pendingSeek = 0;
  listened = 0;
  lastTick = 0;
  reported = 0;
  ordered = null;
  radioFrom = null;
  sleepTimer = null;
  ctx = null;
  eqNodes = null;

  init() {
    if (this.els.length) return;
    for (let i = 0; i < 2; i++) {
      const el = new Audio();
      el.preload = "auto";
      this.bind(el);
      this.els.push(el);
    }
    this.mediaSession();
    this.restore();
    setInterval(() => this.report(false), 60000);
    setInterval(() => this.saveQueue(), 15000);
    addEventListener("pagehide", () => {
      this.report(true);
      this.saveQueue(true);
    });
  }

  get el() {
    return this.els[this.active];
  }

  bind(el) {
    const mine = () => el === this.el;
    el.addEventListener("timeupdate", () => {
      if (!mine()) return;
      const now = el.currentTime;
      if (this.playing && this.lastTick && now > this.lastTick && now - this.lastTick < 2) this.listened += now - this.lastTick;
      this.lastTick = now;
      this.time = now;
      this.maybeCrossfade();
      this.maybeExtend();
    });
    el.addEventListener("durationchange", () => {
      if (mine() && isFinite(el.duration)) this.duration = el.duration;
    });
    el.addEventListener("progress", () => {
      if (mine() && el.buffered.length) this.buffered = el.buffered.end(el.buffered.length - 1);
    });
    el.addEventListener("playing", () => {
      if (!mine()) return;
      this.playing = true;
      this.loading = false;
      this.failures = 0;
      this.error = null;
      this.positionState();
    });
    el.addEventListener("pause", () => {
      if (mine() && !this.fading) this.playing = false;
    });
    el.addEventListener("waiting", () => {
      if (mine()) this.loading = true;
    });
    el.addEventListener("seeked", () => mine() && this.positionState());
    el.addEventListener("ended", () => mine() && this.onEnded());
    el.addEventListener("error", () => mine() && this.onError());
  }

  // Coda

  load(list, start = 0, { play = true, shuffle = false, at = 0 } = {}) {
    this.init();
    const items = songOnly(list);
    if (!items.length) return;
    this.report(true);
    this.cancelFade();
    this.ordered = null;
    this.shuffle = shuffle;
    if (shuffle) {
      this.ordered = items;
      const first = items[start] || items[0];
      this.queue = [first, ...shuffled(items.filter((x) => x !== first))];
      this.index = 0;
    } else {
      this.queue = items;
      this.index = Math.max(0, Math.min(start, items.length - 1));
    }
    this.radioFrom = null;
    this.startCurrent(play, at);
    this.saveQueue();
  }

  playList(list, start = 0, opts) {
    this.load(list, start, opts);
  }

  playNext(list) {
    const items = songOnly(Array.isArray(list) ? list : [list]);
    if (!items.length) return;
    if (!this.current) return this.load(items);
    const q = this.queue.slice();
    q.splice(this.index + 1, 0, ...items);
    this.queue = q;
    toast(items.length === 1 ? "Riprodurrò «" + items[0].title + "» dopo questo brano" : items.length + " brani riprodotti dopo questo");
    this.saveQueue();
  }

  enqueue(list) {
    const items = songOnly(Array.isArray(list) ? list : [list]);
    if (!items.length) return;
    if (!this.current) return this.load(items);
    this.queue = [...this.queue, ...items];
    toast(items.length === 1 ? "«" + items[0].title + "» aggiunto alla coda" : items.length + " brani aggiunti alla coda");
    this.saveQueue();
  }

  jump(i) {
    if (i < 0 || i >= this.queue.length) return;
    this.report(true);
    this.cancelFade();
    this.index = i;
    this.startCurrent(true);
    this.saveQueue();
  }

  remove(i) {
    if (i === this.index) {
      const q = this.queue.slice();
      q.splice(i, 1);
      this.queue = q;
      if (!q.length) return this.stop();
      this.index = Math.min(i, q.length - 1);
      this.startCurrent(this.playing);
    } else {
      const q = this.queue.slice();
      q.splice(i, 1);
      this.queue = q;
      if (i < this.index) this.index--;
    }
    this.saveQueue();
  }

  move(from, to) {
    if (from === to || from < 0 || to < 0 || from >= this.queue.length || to >= this.queue.length) return;
    const q = this.queue.slice();
    const [it] = q.splice(from, 1);
    q.splice(to, 0, it);
    const cur = this.current;
    this.queue = q;
    this.index = q.indexOf(cur);
    this.saveQueue();
  }

  clearUpcoming() {
    this.queue = this.queue.slice(0, this.index + 1);
    this.saveQueue();
  }

  stop() {
    this.report(true);
    this.cancelFade();
    this.els.forEach((e) => {
      e.pause();
      e.removeAttribute("src");
      e.load();
    });
    this.queue = [];
    this.index = -1;
    this.playing = false;
    this.time = this.duration = 0;
    this.saveQueue();
  }

  setShuffle(on) {
    if (on === this.shuffle) return;
    const cur = this.current;
    if (on) {
      this.ordered = this.queue.slice();
      const rest = this.queue.filter((_, i) => i !== this.index);
      this.queue = cur ? [cur, ...shuffled(rest)] : shuffled(rest);
      this.index = cur ? 0 : -1;
    } else if (this.ordered) {
      const known = new Set(this.ordered);
      // Brani aggiunti mentre era attivo il casuale restano in fondo.
      this.queue = [...this.ordered, ...this.queue.filter((x) => !known.has(x))];
      this.index = this.queue.indexOf(cur);
      this.ordered = null;
    }
    this.shuffle = on;
    this.saveQueue();
  }

  cycleRepeat() {
    this.repeat = this.repeat === "off" ? "all" : this.repeat === "all" ? "one" : "off";
  }

  // Riproduzione

  startCurrent(play = true, at = 0) {
    const it = this.current;
    if (!it) return;
    const el = this.el;
    this.time = at;
    this.duration = it.duration || 0;
    this.buffered = 0;
    this.listened = 0;
    this.lastTick = at;
    this.reported = 0;
    this.error = null;
    this.alt = !OPUS || settings.quality === "aac";
    el.volume = this.muted ? 0 : this.volume;
    el.src = audioUrl(it.videoId, this.alt);
    this.pendingSeek = at;
    if (at) el.currentTime = at;
    this.metadata();
    if (play) {
      this.loading = true;
      this.resumeContext();
      el.play().catch((e) => {
        if (e.name === "NotAllowedError") {
          this.loading = false;
          this.playing = false;
        }
      });
    } else {
      this.playing = false;
    }
  }

  toggle() {
    if (!this.current) return;
    const el = this.el;
    if (!el.src) return this.startCurrent(true, this.pendingSeek);
    if (el.paused) {
      this.resumeContext();
      el.play().catch(() => {});
    } else {
      el.pause();
      this.report(false);
      this.saveQueue();
    }
  }

  next(auto = false) {
    if (!this.queue.length) return;
    this.report(true);
    this.cancelFade();
    if (this.sleep && this.sleep.track && auto) {
      this.sleep = null;
      this.el.pause();
      return;
    }
    if (this.index + 1 < this.queue.length) this.index++;
    else if (this.repeat === "all") this.index = 0;
    else {
      this.el.pause();
      this.el.currentTime = 0;
      return;
    }
    this.startCurrent(true);
    this.saveQueue();
  }

  prev() {
    if (!this.queue.length) return;
    if (this.el.currentTime > 4 || this.index === 0) {
      this.seek(0);
      return;
    }
    this.report(true);
    this.cancelFade();
    this.index--;
    this.startCurrent(true);
    this.saveQueue();
  }

  seek(t) {
    const el = this.el;
    if (!el.src) {
      this.pendingSeek = t;
      this.time = t;
      return;
    }
    el.currentTime = Math.max(0, Math.min(t, (this.duration || el.duration || 0) - 0.25));
    this.time = el.currentTime;
    this.lastTick = el.currentTime;
  }

  setVolume(v) {
    this.volume = Math.max(0, Math.min(1, v));
    this.muted = this.volume === 0;
    if (!this.fading) this.el.volume = this.volume;
  }

  toggleMute() {
    this.muted = !this.muted;
    if (!this.fading) this.el.volume = this.muted ? 0 : this.volume;
  }

  onEnded() {
    if (this.repeat === "one") {
      this.report(true);
      this.el.currentTime = 0;
      this.listened = 0;
      this.el.play().catch(() => {});
      return;
    }
    this.next(true);
  }

  async onError() {
    const it = this.current;
    if (!it) return;
    // Opus rifiutato dal browser: un tentativo con AAC dallo stesso punto.
    if (!this.alt) {
      this.alt = true;
      const at = this.time;
      this.el.src = audioUrl(it.videoId, true);
      if (at) this.el.currentTime = at;
      this.el.play().catch(() => {});
      return;
    }
    let reason = "Questo brano non si riesce a riprodurre";
    try {
      await get("/api/stream/" + it.videoId + "?alt=1");
    } catch (e) {
      reason = e.message;
    }
    if (it !== this.current) return;
    this.loading = false;
    this.playing = false;
    this.error = reason;
    this.failures++;
    toast("«" + it.title + "»: " + reason);
    // Tre errori di fila: ci si ferma invece di scorrere tutta la coda.
    if (this.failures < 3 && this.index + 1 < this.queue.length) setTimeout(() => it === this.current && this.next(true), 1200);
  }

  // Crossfade: il brano successivo parte sull'altro elemento e i volumi si incrociano.

  maybeCrossfade() {
    const secs = settings.crossfade;
    if (!secs || this.fading || this.repeat === "one" || !this.duration || this.duration < secs * 3) return;
    if (this.duration - this.time > secs || !this.playing) return;
    const nextIndex = this.index + 1 < this.queue.length ? this.index + 1 : this.repeat === "all" ? 0 : -1;
    if (nextIndex < 0 || (this.sleep && this.sleep.track)) return;
    this.report(true);
    const from = this.el;
    this.active = 1 - this.active;
    this.index = nextIndex;
    this.startCurrent(true);
    const to = this.el;
    to.volume = 0;
    const target = () => (this.muted ? 0 : this.volume);
    const t0 = performance.now();
    const ms = secs * 1000;
    this.fading = { from, timer: setInterval(() => {
      const k = Math.min(1, (performance.now() - t0) / ms);
      // Curva a potenza costante: il volume percepito non cala a metà sfumatura.
      to.volume = target() * Math.sin((k * Math.PI) / 2);
      from.volume = target() * Math.cos((k * Math.PI) / 2);
      if (k >= 1) this.cancelFade();
    }, 50) };
    this.saveQueue();
  }

  cancelFade() {
    if (!this.fading) return;
    clearInterval(this.fading.timer);
    this.fading.from.pause();
    this.fading.from.removeAttribute("src");
    this.fading = null;
    this.el.volume = this.muted ? 0 : this.volume;
  }

  // Riproduzione automatica: verso la fine della coda arriva la radio del brano.

  async maybeExtend() {
    if (!settings.autoplay || this.repeat !== "off" || !this.current) return;
    if (this.index < this.queue.length - 2) return;
    const seed = this.current.videoId;
    if (this.radioFrom === seed) return;
    this.radioFrom = seed;
    try {
      const d = await yt("next", { videoId: seed, playlistId: "RDAMVM" + seed });
      const have = new Set(this.queue.map((x) => x.videoId));
      const more = Y.radio(d).filter((x) => !have.has(x.videoId)).slice(0, 25);
      if (more.length) this.queue = [...this.queue, ...more];
    } catch {
      this.radioFrom = null;
    }
  }

  async startRadio(item) {
    this.load([item]);
    this.radioFrom = item.videoId;
    try {
      const d = await yt("next", { videoId: item.videoId, playlistId: "RDAMVM" + item.videoId });
      const more = Y.radio(d).filter((x) => x.videoId !== item.videoId);
      if (this.current && this.current.videoId === item.videoId) this.queue = [...this.queue, ...more];
    } catch (e) {
      toast(e.message);
    }
  }

  // Elenco di un endpoint "watch" (casuale e mix di un artista, playlist radio).
  async playWatch(w, shuffle = false) {
    try {
      const d = await yt("next", { videoId: w.videoId || undefined, playlistId: w.playlistId, params: w.params || undefined });
      const items = Y.radio(d);
      if (!items.length) throw new Error("Nessun brano da riprodurre");
      this.load(items, 0, { shuffle });
    } catch (e) {
      toast(e.message);
    }
  }

  // Timer di spegnimento: minuti oppure fine del brano; gli ultimi 8 secondi sfumano.

  setSleep(value) {
    clearTimeout(this.sleepTimer);
    if (!value) {
      this.sleep = null;
      return;
    }
    if (value === "track") {
      this.sleep = { track: true };
      return;
    }
    const until = Date.now() + value * 60000;
    this.sleep = { until };
    this.sleepTimer = setTimeout(() => this.sleepFade(), Math.max(0, value * 60000 - 8000));
  }

  sleepFade() {
    const el = this.el;
    const start = el.volume;
    const t0 = performance.now();
    const timer = setInterval(() => {
      const k = Math.min(1, (performance.now() - t0) / 8000);
      el.volume = start * (1 - k);
      if (k >= 1) {
        clearInterval(timer);
        el.pause();
        el.volume = this.muted ? 0 : this.volume;
        this.sleep = null;
      }
    }, 100);
  }

  // Equalizzatore: il grafo Web Audio nasce solo quando lo si attiva, perché
  // un elemento collegato a un AudioContext non si può più scollegare.

  applyEq() {
    const eq = settings.eq;
    if (!eq.enabled && !this.eqNodes) return;
    if (!this.eqNodes) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      this.ctx = new AC();
      const pre = this.ctx.createGain();
      const filters = EQ_FREQS.map((f, i) => {
        const b = this.ctx.createBiquadFilter();
        b.type = i === 0 ? "lowshelf" : i === EQ_FREQS.length - 1 ? "highshelf" : "peaking";
        b.frequency.value = f;
        b.Q.value = 1.1;
        return b;
      });
      filters.reduce((a, b) => (a.connect(b), b), pre).connect(this.ctx.destination);
      this.els.forEach((el) => this.ctx.createMediaElementSource(el).connect(pre));
      this.eqNodes = { pre, filters };
    }
    const on = eq.enabled;
    const t = this.ctx.currentTime;
    this.eqNodes.filters.forEach((f, i) => f.gain.setTargetAtTime(on ? eq.gains[i] || 0 : 0, t, 0.05));
    this.eqNodes.pre.gain.setTargetAtTime(on ? Math.pow(10, (eq.preamp || 0) / 20) : 1, t, 0.05);
    this.resumeContext();
  }

  resumeContext() {
    if (this.ctx && this.ctx.state === "suspended") this.ctx.resume().catch(() => {});
  }

  // Media Session: tasti multimediali, schermata di blocco, notifiche.

  mediaSession() {
    if (!("mediaSession" in navigator)) return;
    const ms = navigator.mediaSession;
    const on = (a, f) => {
      try {
        ms.setActionHandler(a, f);
      } catch {}
    };
    on("play", () => this.toggle());
    on("pause", () => this.toggle());
    on("previoustrack", () => this.prev());
    on("nexttrack", () => this.next());
    on("seekto", (d) => this.seek(d.seekTime));
    on("seekbackward", (d) => this.seek(this.time - (d.seekOffset || 10)));
    on("seekforward", (d) => this.seek(this.time + (d.seekOffset || 10)));
    on("stop", () => this.el.pause());
  }

  metadata() {
    const it = this.current;
    if (!it || !("mediaSession" in navigator)) return;
    navigator.mediaSession.metadata = new MediaMetadata({
      title: it.title,
      artist: Y.artistNames(it) || it.subtitle || "",
      album: it.album ? it.album.name : "",
      artwork: it.thumbnail ? [120, 226, 544].map((s) => ({ src: sized(it.thumbnail, s), sizes: s + "x" + s, type: "image/jpeg" })) : []
    });
    document.title = it.title + " · " + (Y.artistNames(it) || "Fabio Music");
  }

  positionState() {
    if (!("mediaSession" in navigator) || !this.duration) return;
    try {
      navigator.mediaSession.setPositionState({ duration: this.duration, position: Math.min(this.time, this.duration), playbackRate: 1 });
    } catch {}
  }

  // Cronologia: un ascolto conta dai 30 secondi in su; il server unisce i
  // resoconti successivi dello stesso ascolto.

  report(final) {
    const it = this.current;
    const secs = Math.round(this.listened);
    if (!it || secs < 30 || secs === this.reported) return;
    this.reported = secs;
    post("/api/history", { item: it, seconds: secs }, { keepalive: final }).catch(() => {});
  }

  // La coda resta sul server: si riprende da un altro dispositivo.

  saveQueue(now = false) {
    clearTimeout(this.saveTimer);
    const write = () => {
      const data = this.queue.length ? { queue: $state.snapshot(this.queue).slice(0, 500), index: this.index, time: Math.floor(this.time), shuffle: this.shuffle, repeat: this.repeat } : null;
      put("/api/state/queue", { data }, { keepalive: now }).catch(() => {});
    };
    if (now) write();
    else this.saveTimer = setTimeout(write, 1500);
  }

  async restore() {
    try {
      const { data } = await get("/api/state/queue");
      if (!data || !Array.isArray(data.queue) || !data.queue.length || this.queue.length) return;
      this.queue = data.queue;
      this.index = Math.max(0, Math.min(data.index || 0, data.queue.length - 1));
      this.repeat = ["off", "all", "one"].includes(data.repeat) ? data.repeat : "off";
      this.shuffle = !!data.shuffle;
      this.time = data.time || 0;
      this.pendingSeek = data.time || 0;
      this.duration = this.current.duration || 0;
      this.metadata();
    } catch {}
  }
}

export const player = new Player();
