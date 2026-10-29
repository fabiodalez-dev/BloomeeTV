<script>
  // Playlist personale: rinomina, descrizione, aggiungi brani cercandoli,
  // riordina (trascinamento o frecce), rimuovi, duplica, elimina.
  import { onMount } from "svelte";
  import SongRow from "../components/SongRow.svelte";
  import Cover from "../components/Cover.svelte";
  import Icon from "../components/Icon.svelte";
  import Sheet from "../components/Sheet.svelte";
  import * as I from "../lib/icons.js";
  import { get, put, patch, del, post, yt } from "../lib/api.js";
  import { searchPage, searchParams, artistNames } from "../lib/yt.js";
  import { navigate, toast, refreshPlaylists } from "../lib/state.svelte.js";
  import { player } from "../lib/player.svelte.js";
  import { minutes } from "../lib/format.js";
  let { id } = $props();
  let pl = $state(null);
  let error = $state("");
  let editing = $state(false);
  let name = $state("");
  let description = $state("");
  let adding = $state(false);
  let q = $state("");
  let results = $state([]);
  let searching = $state(false);
  let dragFrom = $state(null);
  let over = $state(null);
  onMount(async () => {
    try {
      pl = await get("/api/playlists/" + id);
    } catch (e) {
      error = e.message;
    }
  });
  let total = $derived(pl ? pl.items.reduce((s, t) => s + (t.duration || 0), 0) : 0);
  let cover = $derived(pl && pl.items[0] ? pl.items[0].thumbnail : null);

  async function saveItems(items, message) {
    const before = pl.items;
    pl.items = items;
    try {
      await put("/api/playlists/" + id + "/items", { items });
      if (message) toast(message);
      refreshPlaylists();
    } catch (e) {
      pl.items = before;
      toast(e.message);
    }
  }
  function removeAt(i) {
    const items = pl.items.slice();
    const [gone] = items.splice(i, 1);
    saveItems(items);
    toast("«" + gone.title + "» rimosso", { label: "Annulla", run: () => { const back = pl.items.slice(); back.splice(i, 0, gone); saveItems(back); } });
  }
  function move(from, to) {
    if (to < 0 || to >= pl.items.length || from === to) return;
    const items = pl.items.slice();
    const [it] = items.splice(from, 1);
    items.splice(to, 0, it);
    saveItems(items);
  }
  async function saveMeta(e) {
    e.preventDefault();
    try {
      await patch("/api/playlists/" + id, { name, description });
      pl.name = name.trim();
      pl.description = description.trim();
      editing = false;
      refreshPlaylists();
    } catch (err) {
      toast(err.message);
    }
  }
  async function remove() {
    if (!confirm("Eliminare la playlist «" + pl.name + "»? Non si può annullare.")) return;
    await del("/api/playlists/" + id);
    await refreshPlaylists();
    toast("Playlist eliminata");
    navigate("/library", { replace: true });
  }
  async function duplicate() {
    const d = await post("/api/playlists", { name: pl.name + " (copia)", description: pl.description, items: pl.items });
    await refreshPlaylists();
    navigate("/my/" + d.id);
  }
  let timer;
  function search() {
    clearTimeout(timer);
    const text = q.trim();
    if (!text) return (results = []);
    timer = setTimeout(async () => {
      searching = true;
      try {
        const d = await yt("search", { query: text, params: searchParams.song });
        if (q.trim() === text) results = searchPage(d).items.filter((i) => i.kind === "song");
      } catch (e) {
        toast(e.message);
      } finally {
        searching = false;
      }
    }, 300);
  }
  async function add(it) {
    try {
      await post("/api/playlists/" + id + "/items", { items: [it] });
      pl.items = [...pl.items, it];
      toast("«" + it.title + "» aggiunto");
      refreshPlaylists();
    } catch (e) {
      toast(e.message);
    }
  }
  let inList = $derived(new Set(pl ? pl.items.map((i) => i.videoId) : []));
</script>

{#if error}
  <div class="page"><div class="empty"><p class="title">Playlist non trovata</p><p>{error}</p></div></div>
{:else if pl}
  <div class="page">
    <header class="head">
      <div class="art"><Cover src={cover} size={600} radius="var(--radius-l)" /></div>
      <div class="meta">
        <p class="kind muted">La tua playlist</p>
        {#if editing}
          <form class="edit" onsubmit={saveMeta}>
            <input class="field" bind:value={name} maxlength="120" aria-label="Nome" required />
            <textarea class="field" bind:value={description} rows="3" maxlength="1000" placeholder="Descrizione (facoltativa)" aria-label="Descrizione"></textarea>
            <div class="row"><button class="btn filled">Salva</button><button type="button" class="btn text" onclick={() => (editing = false)}>Annulla</button></div>
          </form>
        {:else}
          <h1 class="display ttl">{pl.name}</h1>
          {#if pl.description}<p class="desc muted">{pl.description}</p>{/if}
          <p class="muted small">{pl.items.length} {pl.items.length === 1 ? "brano" : "brani"}{total ? ", " + minutes(Math.round(total / 60)) : ""}</p>
        {/if}
        <div class="actions">
          <button class="btn filled big" disabled={!pl.items.length} onclick={() => player.playList(pl.items)}><Icon path={I.mdiPlay} /> Riproduci</button>
          <button class="icon-btn tonal bi" disabled={!pl.items.length} onclick={() => player.playList(pl.items, 0, { shuffle: true })} aria-label="Casuale"><Icon path={I.mdiShuffleVariant} /></button>
          <button class="btn tonal big" onclick={() => (adding = true)}><Icon path={I.mdiPlus} /> Aggiungi brani</button>
          <button class="icon-btn tonal bi" onclick={() => ((name = pl.name), (description = pl.description), (editing = true))} aria-label="Modifica nome e descrizione"><Icon path={I.mdiPencil} /></button>
          <button class="icon-btn tonal bi" onclick={duplicate} aria-label="Duplica la playlist"><Icon path={I.mdiContentCopy} /></button>
          <button class="icon-btn tonal bi" onclick={remove} aria-label="Elimina la playlist"><Icon path={I.mdiDelete} /></button>
        </div>
      </div>
    </header>

    {#if pl.items.length}
      <ol class="group list">
        {#each pl.items as t, i (i + t.videoId)}
          <li
            class="it"
            class:over={over === i}
            draggable="true"
            ondragstart={() => (dragFrom = i)}
            ondragover={(e) => (e.preventDefault(), (over = i))}
            ondrop={() => (move(dragFrom, i), (dragFrom = over = null))}
            ondragend={() => (dragFrom = over = null)}
          >
            <span class="grip" aria-hidden="true"><Icon path={I.mdiDragHorizontalVariant} size={20} /></span>
            <div class="song"><SongRow item={t} onplay={() => player.playList(pl.items, i)} context={{ removeLabel: "Rimuovi da questa playlist", remove: () => removeAt(i) }} /></div>
            <span class="ord">
              <button class="icon-btn sm" disabled={i === 0} onclick={() => move(i, i - 1)} aria-label="Sposta su"><Icon path={I.mdiArrowUp} size={18} /></button>
              <button class="icon-btn sm" disabled={i === pl.items.length - 1} onclick={() => move(i, i + 1)} aria-label="Sposta giù"><Icon path={I.mdiArrowDown} size={18} /></button>
            </span>
          </li>
        {/each}
      </ol>
    {:else}
      <div class="empty"><p class="title">La playlist è vuota</p><p>Aggiungi brani cercandoli qui, oppure da qualsiasi brano con «Aggiungi a playlist».</p><button class="btn filled" onclick={() => (adding = true)}>Aggiungi brani</button></div>
    {/if}
  </div>

  {#if adding}
    <Sheet title="Aggiungi a «{pl.name}»" onclose={() => (adding = false)} wide>
      <input class="field" bind:value={q} oninput={search} placeholder="Cerca un brano" aria-label="Cerca un brano da aggiungere" {@attach (n) => n.focus()} />
      <div class="results">
        {#if searching}<p class="muted pad">Cerco…</p>{/if}
        {#each results as r (r.videoId)}
          <div class="res">
            <Cover src={r.thumbnail} size={96} radius="var(--radius-xs)" />
            <span class="rt"><span class="ellipsis t">{r.title}</span><span class="ellipsis muted s">{artistNames(r)}</span></span>
            {#if inList.has(r.videoId)}
              <span class="icon-btn on" aria-label="Già nella playlist"><Icon path={I.mdiCheck} /></span>
            {:else}
              <button class="icon-btn tonal" onclick={() => add(r)} aria-label="Aggiungi {r.title}"><Icon path={I.mdiPlus} /></button>
            {/if}
          </div>
        {/each}
      </div>
    </Sheet>
  {/if}
{:else}
  <div class="page"><span class="skeleton sk"></span></div>
{/if}

<style>
  .head { display: grid; grid-template-columns: minmax(180px, 280px) minmax(0, 1fr); gap: clamp(20px, 4vw, 48px); align-items: end; margin: 12px 0 28px; }
  .art { box-shadow: var(--shadow); border-radius: var(--radius-l); }
  .kind { margin: 0 0 6px; font-weight: 600; }
  .ttl { font-size: clamp(2rem, 1.2rem + 3.2vw, 4.4rem); overflow-wrap: anywhere; }
  .desc { margin: 10px 0 0; white-space: pre-line; max-width: 70ch; }
  .small { margin: 8px 0 0; }
  .actions { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin-top: 20px; }
  .bi { width: 56px; height: 56px; }
  .edit { display: flex; flex-direction: column; gap: 8px; max-width: 560px; }
  .row { display: flex; gap: 8px; }
  .list { list-style: none; margin: 0; padding: 0; }
  .it { display: flex; align-items: center; }
  .it.over { box-shadow: inset 0 2px 0 var(--primary); }
  .grip { color: var(--faint); padding-left: 8px; cursor: grab; }
  .song { flex: 1; min-width: 0; }
  .song :global(.row) { background: transparent !important; }
  .ord { display: flex; padding-right: 4px; }
  .sm { width: 34px; height: 34px; }
  .sm:disabled { opacity: 0.3; }
  @media (hover: hover) { .ord { opacity: 0; } .it:hover .ord, .it:focus-within .ord { opacity: 1; } }
  .results { margin-top: 10px; min-height: 200px; }
  .res { display: flex; align-items: center; gap: 12px; padding: 6px 4px; }
  .res :global(.cover) { width: 48px; }
  .rt { flex: 1; min-width: 0; display: flex; flex-direction: column; }
  .t { font-weight: 600; }
  .s { font-size: 0.85rem; }
  .pad { padding: 8px; }
  .sk { display: block; height: 320px; border-radius: var(--radius-l); }
  @media (max-width: 700px) { .head { grid-template-columns: 1fr; } .art { width: min(64vw, 260px); justify-self: center; } }
</style>
