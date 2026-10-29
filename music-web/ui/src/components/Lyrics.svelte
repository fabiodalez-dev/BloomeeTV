<script>
  // Testi sincronizzati, come in Mochy: riga attiva grande, parole che si
  // riempiono a tempo (quando la fonte le ha), tocco su una riga per saltarci.
  import { get, yt } from "../lib/api.js";
  import { lyricsBrowseId, plainLyrics, artistNames } from "../lib/yt.js";
  import { player } from "../lib/player.svelte.js";
  let { big = false } = $props();
  let data = $state(null);
  let status = $state("idle"); // idle | loading | ready | none | error
  let box;
  let active = $state(-1);
  let userScroll = 0;
  let raf;
  let loadedFor = null;

  async function load(it) {
    loadedFor = it.videoId;
    status = "loading";
    data = null;
    active = -1;
    try {
      const q = new URLSearchParams({ videoId: it.videoId, title: it.title, artist: artistNames(it) || it.subtitle || "" });
      if (it.album) q.set("album", it.album.name);
      if (it.duration) q.set("duration", it.duration);
      let found = (await get("/api/lyrics?" + q)).lyrics;
      if (!found) {
        const next = await yt("next", { videoId: it.videoId });
        const id = lyricsBrowseId(next);
        if (id) found = plainLyrics(await yt("browse", { browseId: id }));
      }
      if (loadedFor !== it.videoId) return;
      data = found;
      status = found ? "ready" : "none";
    } catch {
      if (loadedFor === it.videoId) status = "error";
    }
  }

  $effect(() => {
    const it = player.current;
    if (it && it.videoId !== loadedFor) load(it);
  });

  function tick() {
    raf = requestAnimationFrame(tick);
    if (!data || !data.synced || !box) return;
    const t = (player.el ? player.el.currentTime : player.time) + 0.12;
    let i = -1;
    for (let k = 0; k < data.lines.length; k++) {
      if (data.lines[k].t <= t) i = k;
      else break;
    }
    if (i !== active) {
      active = i;
      if (Date.now() - userScroll > 4000) {
        const el = box.querySelector('[data-i="' + i + '"]');
        el?.scrollIntoView({ block: "center", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
      }
    }
    if (data.words && i >= 0) {
      const line = box.querySelector('[data-i="' + i + '"]');
      line?.querySelectorAll("[data-t]").forEach((w) => {
        const s = +w.dataset.t, e = +w.dataset.e;
        w.style.setProperty("--p", t <= s ? "0%" : t >= e ? "100%" : ((t - s) / (e - s)) * 100 + "%");
      });
    }
  }

  $effect(() => {
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  });

  function onscroll() {
    userScroll = Date.now();
  }
</script>

<div class="lyrics" class:big bind:this={box} role="region" aria-label="Testo del brano" onwheel={onscroll} ontouchmove={onscroll}>
  {#if status === "loading"}
    <p class="note">Cerco il testo…</p>
  {:else if status === "none"}
    <p class="note">Nessun testo trovato per questo brano.</p>
  {:else if status === "error"}
    <p class="note">Il testo non si carica: controlla la connessione.</p>
  {:else if data}
    {#each data.lines as line, i}
      {#if data.synced}
        <button class="line" data-i={i} class:on={i === active} class:past={i < active} onclick={() => player.seek(line.t)}>
          {#if data.words && line.words}
            {#each line.words as w}<span class="w" data-t={w.t} data-e={w.end}>{w.text}</span>{/each}
          {:else}{line.text}{/if}
        </button>
      {:else}
        <p class="line plain">{line.text || " "}</p>
      {/if}
    {/each}
    <p class="src">Testo da {data.source}</p>
  {/if}
</div>

<style>
  .lyrics { height: 100%; overflow-y: auto; padding: 30vh 8px 40vh; scrollbar-width: none; mask-image: linear-gradient(transparent, black 14%, black 80%, transparent); }
  .lyrics::-webkit-scrollbar { display: none; }
  .line {
    display: block; width: 100%; text-align: left; padding: 6px 4px; margin: 0;
    font-size: clamp(1.4rem, 1rem + 1.2vw, 2rem); line-height: 1.22; font-weight: 760; font-stretch: 112%; letter-spacing: -0.015em;
    color: color-mix(in oklch, var(--on-bg) 34%, transparent); transition: color 0.35s, transform 0.4s var(--ease); transform-origin: left center;
    border-radius: var(--radius-s);
  }
  .big .line { font-size: clamp(1.8rem, 1.1rem + 2.2vw, 3.2rem); }
  .line.past { color: color-mix(in oklch, var(--on-bg) 50%, transparent); }
  .line.on { color: var(--on-bg); transform: scale(1.03); }
  .line:hover { color: color-mix(in oklch, var(--on-bg) 70%, transparent); }
  .on .w {
    --p: 0%;
    background: linear-gradient(90deg, var(--on-bg) var(--p), color-mix(in oklch, var(--on-bg) 38%, transparent) var(--p));
    -webkit-background-clip: text; background-clip: text; color: transparent;
  }
  .plain { font-size: 1.25rem; font-weight: 600; color: var(--on-bg); padding: 2px 4px; }
  .note { color: var(--muted); font-size: 1.1rem; text-align: center; }
  .src { color: var(--faint); font-size: 0.85rem; margin-top: 28px; padding: 0 4px; }
</style>
