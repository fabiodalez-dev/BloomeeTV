<script>
  // Coda: brano attuale, prossimi brani riordinabili (trascinamento o frecce), salvataggio come playlist.
  import Cover from "./Cover.svelte";
  import Icon from "./Icon.svelte";
  import * as I from "../lib/icons.js";
  import { player } from "../lib/player.svelte.js";
  import { ui } from "../lib/state.svelte.js";
  import { artistNames } from "../lib/yt.js";
  let dragFrom = $state(null);
  let over = $state(null);
  let upcoming = $derived(player.queue.map((it, i) => ({ it, i })).filter((x) => x.i > player.index));
  function drop(i) {
    if (dragFrom != null && dragFrom !== i) player.move(dragFrom, i);
    dragFrom = over = null;
  }
</script>

<div class="queue">
  {#if player.current}
    <h3 class="label muted sub">In riproduzione</h3>
    <div class="now">
      <Cover src={player.current.thumbnail} size={96} radius="var(--radius-xs)" />
      <div class="txt"><div class="ellipsis t">{player.current.title}</div><div class="ellipsis muted s">{artistNames(player.current)}</div></div>
    </div>
  {/if}
  <div class="bar">
    <h3 class="label muted sub">Prossimi brani · {upcoming.length}</h3>
    <div class="tools">
      <button class="btn text" disabled={!player.queue.length} onclick={() => (ui.addTo = $state.snapshot(player.queue))}><Icon path={I.mdiContentSaveOutline} size={20} /> Salva come playlist</button>
      {#if upcoming.length}<button class="btn text" onclick={() => player.clearUpcoming()}>Svuota</button>{/if}
    </div>
  </div>
  {#if !upcoming.length}
    <p class="muted empty-q">Non c'è altro in coda. Con la riproduzione automatica attiva, arriva la radio del brano.</p>
  {/if}
  <ol class="list">
    {#each upcoming as { it, i } (i + it.videoId)}
      <li
        class="q"
        class:over={over === i}
        draggable="true"
        ondragstart={() => (dragFrom = i)}
        ondragover={(e) => (e.preventDefault(), (over = i))}
        ondragleave={() => over === i && (over = null)}
        ondrop={() => drop(i)}
        ondragend={() => (dragFrom = over = null)}
      >
        <span class="grip" aria-hidden="true"><Icon path={I.mdiDragHorizontalVariant} size={20} /></span>
        <button class="pick" onclick={() => player.jump(i)}>
          <Cover src={it.thumbnail} size={96} radius="var(--radius-xs)" />
          <span class="txt"><span class="ellipsis t">{it.title}</span><span class="ellipsis muted s">{artistNames(it) || it.subtitle}</span></span>
        </button>
        <button class="icon-btn sm" aria-label="Sposta su" disabled={i === player.index + 1} onclick={() => player.move(i, i - 1)}><Icon path={I.mdiArrowUp} size={18} /></button>
        <button class="icon-btn sm" aria-label="Sposta giù" disabled={i === player.queue.length - 1} onclick={() => player.move(i, i + 1)}><Icon path={I.mdiArrowDown} size={18} /></button>
        <button class="icon-btn sm" aria-label="Rimuovi {it.title} dalla coda" onclick={() => player.remove(i)}><Icon path={I.mdiClose} size={18} /></button>
      </li>
    {/each}
  </ol>
</div>

<style>
  .queue { padding: 8px 4px 24px; }
  .sub { margin: 14px 8px 8px; font-weight: 600; }
  .now { display: flex; gap: 12px; align-items: center; padding: 8px; border-radius: var(--radius-m); background: var(--primary-container); color: var(--on-primary-container); }
  .now .s { color: inherit; opacity: 0.8; }
  .now :global(.cover), .pick :global(.cover) { width: 44px; }
  .bar { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 4px; margin-top: 8px; }
  .tools { display: flex; }
  .tools .btn { height: 36px; font-size: 0.88rem; }
  .list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 2px; }
  .q { display: flex; align-items: center; gap: 2px; padding: 4px; border-radius: var(--radius-s); }
  .q:hover { background: var(--surface-2); }
  .q.over { box-shadow: inset 0 2px 0 var(--primary); }
  .grip { color: var(--faint); cursor: grab; padding: 0 2px; }
  .pick { display: flex; align-items: center; gap: 12px; flex: 1; min-width: 0; text-align: left; }
  .txt { display: flex; flex-direction: column; min-width: 0; }
  .t { font-weight: 600; }
  .s { font-size: 0.85rem; }
  .sm { width: 34px; height: 34px; }
  .sm:disabled { opacity: 0.3; }
  .empty-q { padding: 8px; font-size: 0.92rem; }
  @media (hover: hover) { .q .sm { opacity: 0; } .q:hover .sm, .q:focus-within .sm { opacity: 1; } }
</style>
