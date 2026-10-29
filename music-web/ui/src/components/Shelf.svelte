<script>
  // Sezione di una pagina YouTube Music: brani in colonne raggruppate,
  // album/playlist/artisti in una riga che scorre.
  import Card from "./Card.svelte";
  import SongRow from "./SongRow.svelte";
  import Icon from "./Icon.svelte";
  import { mdiChevronRight } from "../lib/icons.js";
  import { hrefOf, navigate } from "../lib/state.svelte.js";
  import { player } from "../lib/player.svelte.js";
  let { section, limit = 16 } = $props();
  let songs = $derived(section.items.filter((i) => i.kind === "song"));
  // Elenchi di brani (righe) in colonne; video e card in riga che scorre.
  let mostlySongs = $derived(songs.length >= section.items.length * 0.6 && songs.every((s) => s.row));
  let columns = $derived.by(() => {
    const list = songs.slice(0, limit);
    const out = [];
    for (let i = 0; i < list.length; i += 4) out.push(list.slice(i, i + 4));
    return out;
  });
  let more = $derived(section.more ? hrefOf({ browseId: section.more.browseId, params: section.more.params }) : section.search ? "/search?q=" + encodeURIComponent(section.search.query) : null);
</script>

<section class="shelf">
  <div class="section-head">
    <h2 class="title">{section.title}</h2>
    {#if more}<a class="btn text" href={more} onclick={(e) => (e.preventDefault(), navigate(more))}>Tutti <Icon path={mdiChevronRight} size={20} /></a>{/if}
  </div>
  {#if mostlySongs}
    <div class="scroll-x cols">
      {#each columns as col}
        <div class="group col" role="list">
          {#each col as item}
            <SongRow {item} onplay={() => player.playList(songs, songs.indexOf(item))} />
          {/each}
        </div>
      {/each}
    </div>
  {:else}
    <div class="scroll-x">
      {#each section.items as item (item.videoId + "|" + item.browseId + "|" + item.title)}
        <Card {item} />
      {/each}
    </div>
  {/if}
</section>

<style>
  .shelf { min-width: 0; }
  .cols { gap: 12px; }
  .col { width: min(420px, 86vw); flex: none; }
</style>
