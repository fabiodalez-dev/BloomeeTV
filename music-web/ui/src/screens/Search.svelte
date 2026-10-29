<script>
  // Ricerca: suggerimenti mentre si scrive, poi Tutto / Brani / Album /
  // Artisti / Playlist con "Altri risultati" per i filtri.
  import { onMount, untrack } from "svelte";
  import Shelf from "../components/Shelf.svelte";
  import SongRow from "../components/SongRow.svelte";
  import Card from "../components/Card.svelte";
  import Icon from "../components/Icon.svelte";
  import { mdiMagnify, mdiClose, mdiHistory, mdiArrowLeft } from "../lib/icons.js";
  import { yt } from "../lib/api.js";
  import { parseSections, searchParams, searchPage, suggestions } from "../lib/yt.js";
  import { route, navigate, session, hrefOf } from "../lib/state.svelte.js";
  import { player } from "../lib/player.svelte.js";
  import Cover from "../components/Cover.svelte";
  const KINDS = [["all", "Tutto"], ["song", "Brani"], ["album", "Album"], ["artist", "Artisti"], ["playlist", "Playlist"]];
  const recentKey = "fm-recent-searches-" + session.user.id;
  let q = $state(route.query.q || "");
  let kind = $state(route.query.k || "all");
  let sugg = $state(null);
  let sections = $state([]);
  let items = $state([]);
  // "Tutto" arriva come elenco piatto (da ottobre 2026) più il risultato migliore.
  let mixed = $state([]);
  let next = $state(null);
  let loading = $state(false);
  let error = $state("");
  let focused = $state(!route.query.q);
  let input;
  let recent = $state(readRecent());
  let timer;
  let ctrl;

  function readRecent() {
    try {
      return JSON.parse(localStorage.getItem(recentKey) || "[]");
    } catch {
      return [];
    }
  }
  function remember(text) {
    recent = [text, ...recent.filter((r) => r.toLowerCase() !== text.toLowerCase())].slice(0, 12);
    try {
      localStorage.setItem(recentKey, JSON.stringify(recent));
    } catch {}
  }
  function forget(text) {
    recent = recent.filter((r) => r !== text);
    try {
      localStorage.setItem(recentKey, JSON.stringify(recent));
    } catch {}
  }

  function typed() {
    clearTimeout(timer);
    const text = q.trim();
    if (!text) {
      sugg = null;
      return;
    }
    timer = setTimeout(async () => {
      try {
        const d = await yt("music/get_search_suggestions", { input: text });
        if (q.trim() === text) sugg = suggestions(d);
      } catch {}
    }, 180);
  }

  function submit(text = q, k = kind) {
    text = text.trim();
    if (!text) return;
    q = text;
    remember(text);
    focused = false;
    input?.blur();
    navigate("/search?q=" + encodeURIComponent(text) + (k !== "all" ? "&k=" + k : ""), { replace: !!route.query.q });
  }

  async function run() {
    const text = route.query.q;
    if (!text) return;
    ctrl?.abort();
    ctrl = new AbortController();
    loading = true;
    error = "";
    sections = [];
    items = [];
    mixed = [];
    next = null;
    try {
      const body = { query: text };
      if (kind !== "all") body.params = searchParams[kind];
      const d = await yt("search", body, { signal: ctrl.signal });
      if (kind === "all") {
        sections = parseSections(d).filter((x) => !x.shelf || x.items.length);
        const shown = new Set(sections.flatMap((x) => x.items.map((i) => i.videoId || i.browseId)));
        mixed = searchPage(d).items.filter((i) => !shown.has(i.videoId || i.browseId));
      } else {
        const p = searchPage(d);
        items = p.items.filter((i) => i.kind === kind);
        next = p.next;
      }
    } catch (e) {
      if (e.name !== "AbortError") error = e.message;
    } finally {
      loading = false;
    }
  }

  async function more() {
    if (!next) return;
    loading = true;
    try {
      const d = await yt("search", { continuation: next.token, legacy: next.legacy });
      const p = searchPage(d);
      const have = new Set(items.map((i) => i.videoId || i.browseId));
      items = [...items, ...p.items.filter((i) => i.kind === kind && !have.has(i.videoId || i.browseId))];
      next = p.next;
    } catch (e) {
      error = e.message;
    } finally {
      loading = false;
    }
  }

  function setKind(k) {
    kind = k;
    if (route.query.q) navigate("/search?q=" + encodeURIComponent(route.query.q) + (k !== "all" ? "&k=" + k : ""), { replace: true });
  }

  onMount(() => {
    if (!route.query.q) input?.focus();
  });
  // La pagina resta montata cambiando solo ?q= e ?k=: si cerca di nuovo qui.
  $effect(() => {
    const text = route.query.q, k = route.query.k || "all";
    untrack(() => {
      kind = k;
      if (text) q = text;
      run();
    });
  });

  function key(e) {
    if (e.key === "Escape") {
      if (q) q = "";
      else input.blur();
      sugg = null;
    }
  }
</script>

<div class="page">
  <form class="bar" class:focused onsubmit={(e) => (e.preventDefault(), submit())} role="search">
    <Icon path={mdiMagnify} />
    <input bind:this={input} bind:value={q} oninput={typed} onfocus={() => (focused = true)} onkeydown={key} placeholder="Brani, album, artisti, playlist" aria-label="Cerca" enterkeyhint="search" autocomplete="off" />
    {#if q}<button type="button" class="icon-btn" onclick={() => ((q = ""), (sugg = null), input.focus())} aria-label="Cancella"><Icon path={mdiClose} /></button>{/if}
  </form>

  {#if focused && (!route.query.q || q !== route.query.q)}
    <div class="sugg">
      {#if sugg && q.trim()}
        {#each sugg.queries as s}
          <button class="sline" onclick={() => submit(s)}><Icon path={mdiMagnify} size={20} /> <span class="ellipsis">{s}</span></button>
        {/each}
        {#if sugg.items.length}
          <div class="group sitems">
            {#each sugg.items as it}
              {#if it.kind === "song"}
                <SongRow item={it} onplay={() => player.playList([it])} />
              {:else}
                <a class="srow" href={hrefOf(it)} onclick={(e) => (e.preventDefault(), navigate(hrefOf(it)))}>
                  <span class="sthumb"><Cover src={it.thumbnail} size={96} shape={it.kind === "artist" ? "round" : "square"} radius="var(--radius-xs)" /></span>
                  <span><span class="ellipsis">{it.title}</span><span class="muted s ellipsis">{it.subtitle}</span></span>
                </a>
              {/if}
            {/each}
          </div>
        {/if}
      {:else if recent.length}
        <h2 class="label muted">Ricerche recenti</h2>
        {#each recent as r}
          <div class="sline">
            <button class="rl" onclick={() => submit(r)}><Icon path={mdiHistory} size={20} /> <span class="ellipsis">{r}</span></button>
            <button class="icon-btn" onclick={() => forget(r)} aria-label="Rimuovi {r} dalle ricerche recenti"><Icon path={mdiClose} size={18} /></button>
          </div>
        {/each}
      {:else}
        <div class="empty"><p class="title">Cerca qualcosa da ascoltare</p><p>Un brano, un artista, un album. Premi / da qualsiasi pagina per tornare qui.</p></div>
      {/if}
    </div>
  {:else if route.query.q}
    <div class="scroll-x kinds" role="tablist">
      {#each KINDS as [k, label]}<button role="tab" aria-selected={kind === k} class="chip" class:on={kind === k} onclick={() => setKind(k)}>{label}</button>{/each}
    </div>
    {#if error}
      <div class="empty"><p class="title">La ricerca non è riuscita</p><p>{error}</p><button class="btn tonal" onclick={run}>Riprova</button></div>
    {:else if loading && !sections.length && !items.length}
      <div class="group">{#each Array(8) as _}<span class="skeleton skrow"></span>{/each}</div>
    {:else if kind === "all"}
      {#each sections as s, i (i + s.title)}<Shelf section={s} />{/each}
      {#if mixed.length}
        <div class="group list" role="list">
          {#each mixed as it, i (i + (it.videoId || it.browseId))}
            {#if it.kind === "song"}
              <SongRow item={it} onplay={() => player.playList(mixed.filter((m) => m.kind === "song"), mixed.filter((m) => m.kind === "song").indexOf(it))} />
            {:else if hrefOf(it)}
              <a class="srow wide" href={hrefOf(it)} onclick={(e) => (e.preventDefault(), navigate(hrefOf(it)))}>
                <span class="sthumb"><Cover src={it.thumbnail} size={96} shape={it.kind === "artist" ? "round" : "square"} radius="var(--radius-xs)" /></span>
                <span><span class="ellipsis">{it.title}</span><span class="muted s ellipsis">{it.subtitle}</span></span>
              </a>
            {/if}
          {/each}
        </div>
      {/if}
      {#if !sections.length && !mixed.length}<div class="empty"><p class="title">Nessun risultato per «{route.query.q}»</p><p>Prova con meno parole o controlla l'ortografia.</p></div>{/if}
    {:else if kind === "song"}
      <div class="group list" role="list">
        {#each items as it, i (it.videoId + i)}<SongRow item={it} onplay={() => player.playList(items, i)} />{/each}
      </div>
    {:else}
      <div class="grid">{#each items as it (it.browseId)}<Card item={it} width={170} />{/each}</div>
    {/if}
    {#if kind !== "all" && !items.length && !loading && !error}<div class="empty"><p class="title">Nessun risultato in questa categoria</p></div>{/if}
    {#if next}<div class="moreb"><button class="btn tonal" disabled={loading} onclick={more}>{loading ? "Carico…" : "Altri risultati"}</button></div>{/if}
  {/if}
</div>

<style>
  .bar {
    position: sticky; top: 12px; z-index: 5; display: flex; align-items: center; gap: 10px; height: 60px; padding: 0 8px 0 20px;
    border-radius: 30px; background: var(--surface-2); margin: 4px 0 18px; transition: border-radius 0.3s var(--ease), box-shadow 0.3s;
  }
  .bar.focused { box-shadow: 0 0 0 2px var(--primary); }
  .bar input { flex: 1; min-width: 0; height: 100%; background: none; border: 0; outline: none; font-size: 1.1rem; }
  .sugg { display: flex; flex-direction: column; gap: 2px; }
  .sline { display: flex; align-items: center; gap: 14px; padding: 10px 12px; border-radius: var(--radius-s); text-align: left; font-size: 1.05rem; min-width: 0; }
  .sline:hover { background: var(--surface); }
  .rl { display: flex; align-items: center; gap: 14px; flex: 1; min-width: 0; text-align: left; }
  .sitems { margin-top: 12px; }
  .srow { display: flex; align-items: center; gap: 14px; padding: 8px; min-width: 0; }
  .srow.wide { padding: 8px 14px 8px 8px; min-height: 64px; }
  .srow.wide:hover { background: var(--surface-2); }
  .sthumb { width: 48px; flex: none; }
  .srow > span { display: flex; flex-direction: column; min-width: 0; font-weight: 600; }
  .s { font-size: 0.85rem; font-weight: 500; }
  .label { margin: 8px 12px; }
  .kinds { gap: 8px; margin-bottom: 8px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 22px 16px; margin-top: 16px; }
  .grid :global(.card) { width: 100% !important; }
  .list { margin-top: 12px; }
  .skrow { display: block; height: 64px; }
  .moreb { display: flex; justify-content: center; margin-top: 24px; }
</style>
