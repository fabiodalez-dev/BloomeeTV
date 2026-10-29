<script>
  // Pagina generica di YouTube Music (mood, generi, classifiche, "Tutti").
  import { onMount } from "svelte";
  import Shelf from "../components/Shelf.svelte";
  import Card from "../components/Card.svelte";
  import { yt } from "../lib/api.js";
  import { parseSections, find, text, continuation } from "../lib/yt.js";
  let { id, params = null } = $props();
  let title = $state("");
  let sections = $state([]);
  let loading = $state(true);
  let error = $state("");
  onMount(async () => {
    try {
      const body = { browseId: id };
      if (params) body.params = params;
      const d = await yt("browse", body);
      const h = find(d, "musicHeaderRenderer") || find(d, "musicImmersiveHeaderRenderer") || find(d, "musicResponsiveHeaderRenderer");
      title = (h && text(h.title)) || (id === "FEmusic_charts" ? "Classifiche" : "");
      sections = parseSections(d);
      // Le pagine "Tutti" arrivano come una sola griglia lunga: altre pagine se ci sono.
      let next = continuation(d);
      for (let i = 0; next && i < 4; i++) {
        const more = await yt("browse", { continuation: next.token, legacy: next.legacy });
        sections = [...sections, ...parseSections(more)];
        next = continuation(more);
      }
    } catch (e) {
      error = e.message;
    } finally {
      loading = false;
    }
  });
  let grid = $derived(sections.length === 1 && sections[0].items.every((i) => i.kind !== "song"));
</script>

<div class="page">
  {#if title}<h1 class="display head">{title}</h1>{/if}
  {#if loading}
    <span class="skeleton sk"></span>
  {:else if error}
    <div class="empty"><p class="title">Pagina non disponibile</p><p>{error}</p></div>
  {:else if grid}
    {#if sections[0].title}<h2 class="title">{sections[0].title}</h2>{/if}
    <div class="grid">{#each sections[0].items as item}<Card {item} width={170} />{/each}</div>
  {:else if !sections.length}
    <div class="empty"><p class="title">Qui non c'è niente</p><p>YouTube Music non ha contenuti per questa pagina.</p></div>
  {:else}
    {#each sections as s, i (i + s.title)}<Shelf section={s} limit={40} />{/each}
  {/if}
</div>

<style>
  .head { margin: 12px 0 8px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 22px 16px; margin-top: 16px; }
  .grid :global(.card) { width: 100% !important; }
  .sk { display: block; height: 300px; border-radius: var(--radius-l); margin-top: 20px; }
</style>
