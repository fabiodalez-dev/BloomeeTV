<script>
  // Album o playlist di YouTube Music: copertina, azioni, elenco completo dei brani.
  import { onMount } from "svelte";
  import SongRow from "../components/SongRow.svelte";
  import Cover from "../components/Cover.svelte";
  import Icon from "../components/Icon.svelte";
  import * as I from "../lib/icons.js";
  import { ytAll, post } from "../lib/api.js";
  import { collectionInfo, collectionExtra, fillCollectionTracks, flatItems, continuation } from "../lib/yt.js";
  import { isFavorite, toggleFavorite, navigate, toast, refreshPlaylists, ui } from "../lib/state.svelte.js";
  import { player } from "../lib/player.svelte.js";
  import { time, minutes } from "../lib/format.js";
  let { id } = $props();
  let browseId = $derived(/^(PL|OLAK|RD|LM|UU|FL)/.test(id) ? "VL" + id : id);
  let isAlbum = $derived(browseId.startsWith("MPREb"));
  let info = $state(null);
  let extra = $state({});
  let tracks = $state([]);
  let error = $state("");
  let more = $state(false);
  let saving = $state(false);
  onMount(async () => {
    try {
      const { first, items } = await ytAll("browse", { browseId }, (d) => flatItems(d).filter((i) => i.videoId), continuation, 30);
      info = collectionInfo(first);
      extra = collectionExtra(first);
      const seen = new Set();
      tracks = fillCollectionTracks(items, info, browseId).filter((t) => !seen.has(t.videoId) && seen.add(t.videoId));
    } catch (e) {
      error = e.message;
    }
  });
  let asItem = $derived(info ? { kind: isAlbum ? "album" : "playlist", browseId, title: info.title, subtitle: info.subtitle, thumbnail: info.thumbnail, artists: info.artists } : null);
  let total = $derived(tracks.reduce((s, t) => s + (t.duration || 0), 0));
  async function copy() {
    saving = true;
    try {
      const d = await post("/api/playlists", { name: info.title, description: (isAlbum ? "Album di " : "Copia da YouTube Music") + (isAlbum && info.artists[0] ? info.artists[0].name : ""), items: tracks.slice(0, 5000) });
      await refreshPlaylists();
      toast("Salvata tra le tue playlist", { label: "Apri", run: () => navigate("/my/" + d.id) });
    } catch (e) {
      toast(e.message);
    } finally {
      saving = false;
    }
  }
</script>

{#if error}
  <div class="page"><div class="empty"><p class="title">Non disponibile</p><p>{error}</p></div></div>
{:else if !info}
  <div class="page"><div class="head"><span class="skeleton skc"></span><span class="skeleton skt"></span></div></div>
{:else}
  <div class="page">
    <header class="head">
      <div class="art"><Cover src={info.thumbnail} size={600} radius="var(--radius-l)" alt="Copertina di {info.title}" /></div>
      <div class="meta">
        <p class="kind muted">{isAlbum ? "Album" : "Playlist"}</p>
        <h1 class="display ttl">{info.title}</h1>
        <p class="by">
          {#each info.artists as a, i}{#if i}, {/if}{#if a.id}<a href="/artist/{a.id}" onclick={(e) => (e.preventDefault(), navigate("/artist/" + a.id))}>{a.name}</a>{:else}{a.name}{/if}{/each}
        </p>
        <p class="muted small">{[info.subtitle.replace(/^(Album|Playlist|Singolo|EP)\s*•\s*/i, ""), extra.stats || (tracks.length ? tracks.length + " brani, " + minutes(Math.round(total / 60)) : "")].filter(Boolean).join(" — ")}</p>
        {#if extra.description}<p class="desc muted clamp2">{extra.description}</p>{/if}
        <div class="actions">
          <button class="btn filled big" disabled={!tracks.length} onclick={() => player.playList(tracks)}><Icon path={I.mdiPlay} /> Riproduci</button>
          <button class="icon-btn tonal big-i" disabled={!tracks.length} onclick={() => player.playList(tracks, 0, { shuffle: true })} aria-label="Riproduci in ordine casuale"><Icon path={I.mdiShuffleVariant} /></button>
          <button class="icon-btn tonal big-i" class:on={isFavorite(asItem)} onclick={() => toggleFavorite(asItem)} aria-label={isFavorite(asItem) ? "Rimuovi dalla libreria" : "Salva nella libreria"}><Icon path={isFavorite(asItem) ? I.mdiHeart : I.mdiHeartOutline} /></button>
          <button class="icon-btn tonal big-i" disabled={!tracks.length || saving} onclick={copy} aria-label="Salva come mia playlist" title="Salva come mia playlist"><Icon path={I.mdiContentSaveOutline} /></button>
          <button class="icon-btn tonal big-i" disabled={!tracks.length} onclick={() => player.enqueue(tracks)} aria-label="Aggiungi tutto alla coda" title="Aggiungi alla coda"><Icon path={I.mdiQueueFirstInLastOut} /></button>
        </div>
      </div>
    </header>
    <div class="group list" role="list">
      {#each tracks as t, i (t.videoId)}
        <SongRow item={t} number={isAlbum ? i + 1 : null} onplay={() => player.playList(tracks, i)} />
      {/each}
    </div>
    {#if !tracks.length}<div class="empty"><p class="title">Nessun brano</p><p>YouTube Music non ha restituito brani riproducibili.</p></div>{/if}
  </div>
{/if}

<style>
  .head { display: grid; grid-template-columns: minmax(180px, 300px) minmax(0, 1fr); gap: clamp(20px, 4vw, 48px); align-items: end; margin: 12px 0 28px; }
  .art { width: 100%; box-shadow: var(--shadow); border-radius: var(--radius-l); }
  .kind { margin: 0 0 6px; font-weight: 600; }
  .ttl { font-size: clamp(2rem, 1.2rem + 3.2vw, 4.4rem); overflow-wrap: anywhere; }
  .by { margin: 12px 0 2px; font-weight: 660; font-size: 1.1rem; }
  .by a:hover { text-decoration: underline; }
  .small { margin: 0; font-size: 0.92rem; }
  .desc { margin: 10px 0 0; max-width: 70ch; }
  .actions { display: flex; gap: 8px; align-items: center; margin-top: 20px; flex-wrap: wrap; }
  .big-i { width: 56px; height: 56px; }
  .skc { display: block; aspect-ratio: 1; border-radius: var(--radius-l); }
  .skt { display: block; height: 120px; border-radius: var(--radius-m); }
  @media (max-width: 700px) {
    .head { grid-template-columns: 1fr; justify-items: start; }
    .art { width: min(72vw, 300px); justify-self: center; }
  }
</style>
