<script>
  // Home: saluto, filtri d'umore, ascoltati di recente, playlist personali,
  // poi le sezioni di YouTube Music (personali se l'account è collegato).
  import { onMount } from "svelte";
  import Shelf from "../components/Shelf.svelte";
  import Card from "../components/Card.svelte";
  import Cover from "../components/Cover.svelte";
  import Icon from "../components/Icon.svelte";
  import { mdiPlay, mdiHeart } from "../lib/icons.js";
  import { yt, get } from "../lib/api.js";
  import { parseSections, chips as parseChips, continuation } from "../lib/yt.js";
  import { session, library, navigate } from "../lib/state.svelte.js";
  import { player } from "../lib/player.svelte.js";
  let sections = $state([]);
  let chipList = $state([]);
  let chip = $state(null);
  let recent = $state([]);
  let next = null;
  let loading = $state(true);
  let error = $state("");
  let more = $state(false);
  let sentinel;
  const hour = new Date().getHours();
  const hello = hour < 6 ? "Buonanotte" : hour < 13 ? "Buongiorno" : hour < 18 ? "Buon pomeriggio" : "Buonasera";
  let personal = $derived(!!session.youtube);
  let likedSongs = $derived(library.favorites.filter((f) => f.kind === "song"));
  let myArtists = $derived(library.favorites.filter((f) => f.kind === "artist"));

  async function load() {
    loading = true;
    error = "";
    try {
      const body = { browseId: "FEmusic_home", personal };
      if (chip) body.params = chip.params;
      const d = await yt("browse", body);
      sections = parseSections(d);
      if (!chip) chipList = parseChips(d);
      next = continuation(d);
    } catch (e) {
      error = e.message;
    } finally {
      loading = false;
    }
  }

  async function loadMore() {
    if (!next || more) return;
    more = true;
    try {
      const d = await yt("browse", { continuation: next.token, legacy: next.legacy, personal });
      sections = [...sections, ...parseSections(d)];
      next = continuation(d);
    } catch {
      next = null;
    } finally {
      more = false;
    }
  }

  function pick(c) {
    chip = chip === c ? null : c;
    load();
  }

  onMount(() => {
    load();
    get("/api/history?limit=60").then((d) => {
      const seen = new Set();
      recent = d.items.filter((x) => !seen.has(x.videoId) && seen.add(x.videoId)).slice(0, 12);
    }).catch(() => {});
    const io = new IntersectionObserver((e) => e[0].isIntersecting && loadMore(), { rootMargin: "800px" });
    io.observe(sentinel);
    return () => io.disconnect();
  });
</script>

<div class="page">
  <header class="hero">
    <h1 class="display">{hello},<br />{session.user.displayName}</h1>
  </header>

  {#if chipList.length}
    <div class="scroll-x chips" role="toolbar" aria-label="Filtri">
      {#each chipList as c}<button class="chip" class:on={chip === c} aria-pressed={chip === c} onclick={() => pick(c)}>{c.title}</button>{/each}
    </div>
  {/if}

  {#if !chip}
    <div class="quick">
      {#if likedSongs.length}
        <button class="tile liked" onclick={() => navigate("/library/songs")}>
          <span class="tile-icon"><Icon path={mdiHeart} size={26} /></span>
          <span class="tile-t">Brani che ti piacciono<span class="muted tile-s">{likedSongs.length} brani</span></span>
          <span class="tile-play" role="button" tabindex="0" aria-label="Riproduci i brani che ti piacciono" onclick={(e) => (e.stopPropagation(), player.playList(likedSongs))} onkeydown={(e) => e.key === "Enter" && (e.stopPropagation(), player.playList(likedSongs))}><Icon path={mdiPlay} /></span>
        </button>
      {/if}
      {#each library.playlists.slice(0, likedSongs.length ? 5 : 6) as p (p.id)}
        <a class="tile" href="/my/{p.id}" onclick={(e) => (e.preventDefault(), navigate("/my/" + p.id))}>
          <Cover src={p.thumbnail} size={120} radius="var(--radius-xs)" />
          <span class="tile-t ellipsis">{p.name}<span class="muted tile-s">{p.count} brani</span></span>
        </a>
      {/each}
    </div>

    {#if myArtists.length}
      <section>
        <div class="section-head"><h2 class="title">I tuoi artisti</h2>
          <a class="btn text" href="/library/artists" onclick={(e) => (e.preventDefault(), navigate("/library/artists"))}>Tutti</a>
        </div>
        <div class="scroll-x">
          {#each myArtists.slice(0, 20) as item (item.browseId)}<Card {item} width={132} />{/each}
        </div>
      </section>
    {/if}

    {#if recent.length}
      <section>
        <div class="section-head"><h2 class="title">Ascoltati di recente</h2></div>
        <div class="scroll-x">
          {#each recent as item (item.videoId)}<Card {item} width={150} />{/each}
        </div>
      </section>
    {/if}
  {/if}

  {#if loading}
    {#each [1, 2, 3] as _}
      <div class="section-head"><span class="skeleton sk-title"></span></div>
      <div class="scroll-x">{#each Array(7) as _}<span class="skeleton sk-card"></span>{/each}</div>
    {/each}
  {:else if error}
    <div class="empty"><p class="title">YouTube Music non risponde</p><p>{error}</p><button class="btn tonal" onclick={load}>Riprova</button></div>
  {:else}
    {#each sections as s, i (i + s.title)}<Shelf section={s} />{/each}
  {/if}
  <div bind:this={sentinel} class="sentinel">{#if more}<span class="skeleton sk-title"></span>{/if}</div>
</div>

<style>
  .hero { margin: 12px 0 24px; }
  .chips { gap: 8px; margin-bottom: 22px; }
  .quick { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 260px), 1fr)); gap: 8px; }
  .tile {
    position: relative; display: flex; align-items: center; gap: 12px; padding: 6px; padding-right: 12px; border-radius: var(--radius-s);
    background: var(--surface); text-align: left; min-width: 0; transition: background 0.2s;
  }
  .tile:hover { background: var(--surface-2); }
  .tile :global(.cover) { width: 56px; }
  .tile-t { display: flex; flex-direction: column; font-weight: 680; min-width: 0; }
  .tile-s { font-size: 0.82rem; font-weight: 500; }
  .liked { background: var(--primary-container); color: var(--on-primary-container); }
  .liked:hover { background: color-mix(in oklch, var(--primary-container) 85%, var(--on-primary-container)); }
  .liked .tile-s { color: inherit; opacity: 0.75; }
  .tile-icon { width: 56px; height: 56px; border-radius: var(--radius-xs); display: grid; place-items: center; background: var(--primary); color: var(--on-primary); flex: none; }
  .tile-play { margin-left: auto; width: 40px; height: 40px; border-radius: 50%; display: grid; place-items: center; background: var(--on-primary-container); color: var(--primary-container); flex: none; }
  .sk-title { display: block; width: 220px; height: 26px; border-radius: 8px; }
  .sk-card { display: block; width: 172px; height: 220px; border-radius: var(--radius-m); flex: none; }
  .sentinel { min-height: 40px; }
</style>
