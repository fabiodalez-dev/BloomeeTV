<script>
  // Esplora: novità e classifiche di YouTube Music, poi mood e generi.
  import { onMount } from "svelte";
  import Shelf from "../components/Shelf.svelte";
  import Icon from "../components/Icon.svelte";
  import { mdiChartBox, mdiChevronRight } from "../lib/icons.js";
  import { yt } from "../lib/api.js";
  import { parseSections, moods as parseMoods } from "../lib/yt.js";
  import { navigate } from "../lib/state.svelte.js";
  let sections = $state([]);
  let groups = $state([]);
  let loading = $state(true);
  let error = $state("");
  async function load() {
    loading = true;
    error = "";
    try {
      const [e, m] = await Promise.all([yt("browse", { browseId: "FEmusic_explore" }), yt("browse", { browseId: "FEmusic_moods_and_genres" })]);
      sections = parseSections(e);
      groups = parseMoods(m);
    } catch (err) {
      error = err.message;
    } finally {
      loading = false;
    }
  }
  onMount(load);
  function open(m) {
    navigate("/browse/" + m.browseId + "?params=" + encodeURIComponent(m.params));
  }
</script>

<div class="page">
  <h1 class="display head">Esplora</h1>
  <button class="charts" onclick={() => navigate("/browse/FEmusic_charts")}>
    <Icon path={mdiChartBox} size={28} />
    <span><span class="title">Classifiche</span><span class="muted">I brani e gli artisti più ascoltati adesso</span></span>
    <Icon path={mdiChevronRight} />
  </button>
  {#if loading}
    <div class="section-head"><span class="skeleton sk"></span></div>
  {:else if error}
    <div class="empty"><p class="title">YouTube Music non risponde</p><p>{error}</p><button class="btn tonal" onclick={load}>Riprova</button></div>
  {:else}
    {#each sections as s, i (i + s.title)}<Shelf section={s} />{/each}
    {#each groups as g}
      <section>
        <div class="section-head"><h2 class="title">{g.title}</h2></div>
        <div class="moods">
          {#each g.items as m}
            <button class="mood" style:--stripe={m.color || "var(--primary)"} onclick={() => open(m)}>{m.title}</button>
          {/each}
        </div>
      </section>
    {/each}
  {/if}
</div>

<style>
  .head { margin: 12px 0 24px; }
  .charts { display: flex; align-items: center; gap: 16px; width: 100%; max-width: 560px; padding: 18px 20px; border-radius: var(--radius-l); background: var(--tertiary-container); color: var(--on-tertiary-container); text-align: left; }
  .charts > span { flex: 1; display: flex; flex-direction: column; }
  .charts .muted { color: inherit; opacity: 0.8; }
  .moods { display: grid; grid-template-columns: repeat(auto-fill, minmax(170px, 1fr)); gap: 8px; }
  .mood {
    position: relative; height: 56px; padding: 0 16px 0 22px; border-radius: var(--radius-s); background: var(--surface); text-align: left;
    font-weight: 640; overflow: hidden; transition: background 0.2s, border-radius 0.3s var(--ease);
  }
  .mood::before { content: ""; position: absolute; left: 0; top: 0; bottom: 0; width: 6px; background: var(--stripe); }
  .mood:hover { background: var(--surface-2); border-radius: var(--radius-m); }
  .sk { display: block; width: 240px; height: 26px; border-radius: 8px; }
</style>
