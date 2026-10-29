<script>
  // Libreria: le tue playlist, brani preferiti, album, artisti, cronologia,
  // e (con l'account collegato) le raccolte di YouTube Music.
  import { onMount } from "svelte";
  import Card from "../components/Card.svelte";
  import Cover from "../components/Cover.svelte";
  import SongRow from "../components/SongRow.svelte";
  import Icon from "../components/Icon.svelte";
  import * as I from "../lib/icons.js";
  import { get, post, del, yt } from "../lib/api.js";
  import { flatItems } from "../lib/yt.js";
  import { library, session, navigate, refreshPlaylists, toast } from "../lib/state.svelte.js";
  import { player } from "../lib/player.svelte.js";
  import { ago } from "../lib/format.js";
  let { tab = "playlists" } = $props();
  const TABS = [["playlists", "Playlist"], ["songs", "Brani"], ["albums", "Album"], ["artists", "Artisti"], ["history", "Cronologia"]];
  let tabs = $derived(session.youtube ? [...TABS, ["youtube", "YouTube"]] : TABS);
  let history = $state(null);
  let ytLists = $state(null);
  let creating = $state(false);
  let name = $state("");
  let filter = $state("");
  let songs = $derived(library.favorites.filter((f) => f.kind === "song" && match(f)));
  let albums = $derived(library.favorites.filter((f) => f.kind === "album" || f.kind === "playlist"));
  let artists = $derived(library.favorites.filter((f) => f.kind === "artist"));
  function match(f) {
    const q = filter.trim().toLowerCase();
    return !q || (f.title + " " + (f.artists || []).map((a) => a.name).join(" ")).toLowerCase().includes(q);
  }
  $effect(() => {
    if (tab === "history" && !history) get("/api/history?limit=200").then((d) => (history = d.items)).catch((e) => toast(e.message));
    if (tab === "youtube" && !ytLists) loadYt();
  });
  async function loadYt() {
    try {
      const ids = [["FEmusic_liked_playlists", "Playlist"], ["FEmusic_liked_albums", "Album"], ["FEmusic_library_corpus_artists", "Artisti"]];
      const res = await Promise.all(ids.map(([b]) => yt("browse", { browseId: b, personal: true }).catch(() => null)));
      ytLists = ids.map(([b, title], i) => ({ title, items: res[i] ? flatItems(res[i]).filter((x) => x.browseId) : [] }));
    } catch (e) {
      toast(e.message);
    }
  }
  async function create(e) {
    e.preventDefault();
    if (!name.trim()) return;
    try {
      const d = await post("/api/playlists", { name: name.trim() });
      await refreshPlaylists();
      navigate("/my/" + d.id);
    } catch (err) {
      toast(err.message);
    }
  }
  async function clearHistory() {
    if (!confirm("Cancellare tutta la cronologia di ascolto? Anche il Recap riparte da zero.")) return;
    await del("/api/history");
    history = [];
    toast("Cronologia cancellata");
  }
  function setTab(t) {
    navigate("/library" + (t === "playlists" ? "" : "/" + t), { replace: true });
  }
</script>

<div class="page">
  <div class="top">
    <h1 class="display">Libreria</h1>
    <a class="btn tonal" href="/recap" onclick={(e) => (e.preventDefault(), navigate("/recap"))}><Icon path={I.mdiChartBox} size={20} /> Recap</a>
  </div>
  <div class="scroll-x tabs" role="tablist">
    {#each tabs as [k, label]}<button role="tab" aria-selected={tab === k} class="chip" class:on={tab === k} onclick={() => setTab(k)}>{label}</button>{/each}
  </div>

  {#if tab === "playlists"}
    {#if creating}
      <form class="new" onsubmit={create}>
        <input class="field" bind:value={name} placeholder="Nome della nuova playlist" maxlength="120" aria-label="Nome della nuova playlist" {@attach (n) => n.focus()} />
        <button class="btn filled" disabled={!name.trim()}>Crea</button>
        <button type="button" class="btn text" onclick={() => (creating = false)}>Annulla</button>
      </form>
    {/if}
    <div class="grid">
      {#if !creating}
        <button class="newcard" onclick={() => (creating = true)}><span class="plus"><Icon path={I.mdiPlus} size={36} /></span><span class="t">Nuova playlist</span></button>
      {/if}
      {#each library.playlists as p (p.id)}
        <a class="pl" href="/my/{p.id}" onclick={(e) => (e.preventDefault(), navigate("/my/" + p.id))}>
          <Cover src={p.thumbnail} size={360} radius="var(--radius-m)" />
          <span class="t ellipsis">{p.name}</span>
          <span class="muted s">{p.count} {p.count === 1 ? "brano" : "brani"}</span>
        </a>
      {/each}
    </div>
  {:else if tab === "songs"}
    {#if library.favorites.some((f) => f.kind === "song")}
      <div class="tools">
        <button class="btn filled" onclick={() => player.playList(songs)}><Icon path={I.mdiPlay} /> Riproduci</button>
        <button class="btn tonal" onclick={() => player.playList(songs, 0, { shuffle: true })}><Icon path={I.mdiShuffleVariant} /> Casuale</button>
        <input class="field filter" bind:value={filter} placeholder="Filtra per titolo o artista" aria-label="Filtra i brani" />
      </div>
      <div class="group" role="list">{#each songs as s, i (s.videoId)}<SongRow item={s} onplay={() => player.playList(songs, i)} />{/each}</div>
    {:else}
      <div class="empty"><p class="title">Nessun brano preferito</p><p>Tocca il cuore su un brano per ritrovarlo qui.</p></div>
    {/if}
  {:else if tab === "albums"}
    {#if albums.length}<div class="cards">{#each albums as a (a.browseId)}<Card item={a} width={170} />{/each}</div>
    {:else}<div class="empty"><p class="title">Nessun album salvato</p><p>Apri un album o una playlist di YouTube Music e tocca il cuore.</p></div>{/if}
  {:else if tab === "artists"}
    {#if artists.length}<div class="cards">{#each artists as a (a.browseId)}<Card item={a} width={150} />{/each}</div>
    {:else}<div class="empty"><p class="title">Non segui ancora nessun artista</p><p>Dalla pagina di un artista, tocca il cuore.</p></div>{/if}
  {:else if tab === "history"}
    {#if history === null}<p class="muted">Carico…</p>
    {:else if history.length}
      <div class="tools"><button class="btn text" onclick={clearHistory}><Icon path={I.mdiDelete} size={20} /> Cancella cronologia</button></div>
      <div class="group" role="list">{#each history as h, i (h.playedAt + h.videoId)}<SongRow item={h} extra={ago(h.playedAt) + " — " + (h.artists[0] ? h.artists[0].name : h.subtitle)} onplay={() => player.playList(history, i)} />{/each}</div>
    {:else}<div class="empty"><p class="title">Nessun ascolto</p><p>I brani ascoltati per almeno 30 secondi compaiono qui.</p></div>{/if}
  {:else if tab === "youtube"}
    {#if !ytLists}<p class="muted">Carico la tua libreria di YouTube Music…</p>
    {:else}
      {#each ytLists as g}
        {#if g.items.length}
          <div class="section-head"><h2 class="title">{g.title}</h2></div>
          <div class="cards">{#each g.items as it (it.browseId)}<Card item={it} width={160} />{/each}</div>
        {/if}
      {/each}
    {/if}
  {/if}
</div>

<style>
  .top { display: flex; align-items: end; justify-content: space-between; gap: 12px; margin: 12px 0 20px; }
  .tabs { gap: 8px; margin-bottom: 20px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 22px 16px; }
  .cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 22px 16px; }
  .cards :global(.card) { width: 100% !important; }
  .pl { display: flex; flex-direction: column; gap: 4px; min-width: 0; }
  .pl :global(.cover) { margin-bottom: 6px; transition: transform 0.3s var(--ease-spring); }
  .pl:hover :global(.cover) { transform: scale(1.02); }
  .t { font-weight: 660; }
  .s { font-size: 0.85rem; }
  .newcard { display: flex; flex-direction: column; gap: 10px; text-align: left; }
  .plus { aspect-ratio: 1; width: 100%; border-radius: var(--radius-m); display: grid; place-items: center; background: var(--primary-container); color: var(--on-primary-container); transition: border-radius 0.35s var(--ease); }
  .newcard:hover .plus { border-radius: var(--radius-xl); }
  .new { display: flex; gap: 8px; align-items: center; margin-bottom: 20px; max-width: 640px; }
  .tools { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin-bottom: 14px; }
  .filter { max-width: 320px; height: 44px; margin-left: auto; }
  @media (max-width: 640px) { .filter { margin-left: 0; max-width: none; } }
</style>
