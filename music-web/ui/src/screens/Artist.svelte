<script>
  // Artista: foto a tutta larghezza, nome grande, casuale e mix, biografia, sezioni.
  import { onMount } from "svelte";
  import Shelf from "../components/Shelf.svelte";
  import SongRow from "../components/SongRow.svelte";
  import Icon from "../components/Icon.svelte";
  import * as I from "../lib/icons.js";
  import { yt } from "../lib/api.js";
  import { artistInfo, artistActions } from "../lib/yt.js";
  import { isFavorite, toggleFavorite, navigate } from "../lib/state.svelte.js";
  import { player } from "../lib/player.svelte.js";
  import { sized } from "../lib/format.js";
  let { id } = $props();
  let info = $state(null);
  let actions = $state({});
  let error = $state("");
  let bio = $state(false);
  onMount(async () => {
    try {
      const d = await yt("browse", { browseId: id });
      info = artistInfo(d);
      actions = artistActions(d);
    } catch (e) {
      error = e.message;
    }
  });
  let top = $derived(info ? info.sections.find((s) => s.items.length && s.items.every((i) => i.kind === "song" && i.row)) : null);
  let rest = $derived(info ? info.sections.filter((s) => s !== top) : []);
  let asItem = $derived(info ? { kind: "artist", browseId: id, title: info.name || "", subtitle: "Artista", thumbnail: info.banner, artists: [] } : null);
</script>

{#if error}
  <div class="page"><div class="empty"><p class="title">Artista non disponibile</p><p>{error}</p></div></div>
{:else if !info}
  <div class="hero sk skeleton"></div>
{:else}
  <header class="hero">
    {#if info.banner}<img class="banner" src={sized(info.banner, 1440)} alt="" />{/if}
    <div class="shade"></div>
    <div class="hero-text">
      <h1 class="name">{info.name}</h1>
      <p class="stats">{[info.monthlyListeners, info.subscribers && info.subscribers + " iscritti"].filter(Boolean).join(" — ")}</p>
    </div>
  </header>
  <div class="page body">
    <div class="actions">
      {#if actions.shuffle}<button class="btn filled big" onclick={() => player.playWatch(actions.shuffle, true)}><Icon path={I.mdiShuffleVariant} /> Casuale</button>{/if}
      {#if actions.mix}<button class="btn tonal big" onclick={() => player.playWatch(actions.mix)}><Icon path={I.mdiRadio} /> Mix</button>{/if}
      <button class="icon-btn tonal fav" class:on={isFavorite(asItem)} onclick={() => toggleFavorite(asItem)} aria-label={isFavorite(asItem) ? "Non seguire più" : "Segui (aggiungi ai preferiti)"}>
        <Icon path={isFavorite(asItem) ? I.mdiHeart : I.mdiHeartOutline} />
      </button>
    </div>

    {#if top}
      <section>
        <div class="section-head"><h2 class="title">{top.title || "Brani più famosi"}</h2>
          {#if top.more}<a class="btn text" href="/playlist/{top.more.browseId}" onclick={(e) => (e.preventDefault(), navigate("/playlist/" + top.more.browseId))}>Tutti</a>{/if}
        </div>
        <div class="group" role="list">
          {#each top.items.slice(0, 5) as it, i (it.videoId)}<SongRow item={it} number={i + 1} onplay={() => player.playList(top.items, i)} />{/each}
        </div>
      </section>
    {/if}

    {#each rest as s, i (i + s.title)}<Shelf section={s} />{/each}

    {#if info.description}
      <section class="about">
        <h2 class="title">Biografia</h2>
        <p class:clamp={!bio}>{info.description}</p>
        <button class="btn text" onclick={() => (bio = !bio)}>{bio ? "Mostra meno" : "Leggi tutto"}</button>
      </section>
    {/if}
  </div>
{/if}

<style>
  .hero { position: relative; height: clamp(320px, 52vh, 560px); display: flex; align-items: end; overflow: hidden; background: var(--surface); }
  .sk { display: block; }
  .banner { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: center 25%; }
  .shade { position: absolute; inset: 0; background: linear-gradient(to top, var(--bg) 2%, color-mix(in oklch, var(--bg) 40%, transparent) 40%, transparent 75%); }
  .hero-text { position: relative; padding: 0 clamp(16px, 4vw, 48px) 8px; width: 100%; max-width: 1500px; margin: 0 auto; }
  .name {
    margin: 0; font-size: clamp(3rem, 1rem + 8vw, 8.5rem); line-height: 0.86; font-weight: 900; font-stretch: 151%;
    letter-spacing: -0.045em; font-variation-settings: "opsz" 144; text-wrap: balance; overflow-wrap: break-word;
  }
  @media (max-width: 640px) { .name { font-size: clamp(2.2rem, 10.5vw, 3.6rem); font-stretch: 112%; } }
  .stats { margin: 12px 0 0; color: var(--muted); font-weight: 560; }
  .body { padding-top: 16px; }
  .actions { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
  .fav { width: 56px; height: 56px; }
  .about { margin-top: 36px; max-width: 70ch; }
  .about p { white-space: pre-line; color: var(--muted); }
  .clamp { display: -webkit-box; -webkit-line-clamp: 4; -webkit-box-orient: vertical; overflow: hidden; }
</style>
