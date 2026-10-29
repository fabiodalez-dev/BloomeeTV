<script>
  // Grafico a barre di una sola serie: barre sottili con estremità arrotondate
  // sulla base, 2px di spazio tra le barre, valore al passaggio del mouse o
  // del focus, e la stessa serie anche come tabella.
  let { data = [], unit = "min", label, height = 140, tick = 6 } = $props();
  let hover = $state(null);
  let max = $derived(Math.max(1, ...data.map((d) => d.value)));
</script>

<figure class="chart">
  <div class="plot" style:height="{height}px" role="group" aria-label={label}>
    {#each data as d, i}
      <button
        type="button"
        class="col"
        aria-label="{d.label}: {d.value} {unit}"
        onmouseenter={() => (hover = i)}
        onmouseleave={() => (hover = null)}
        onfocus={() => (hover = i)}
        onblur={() => (hover = null)}
      >
        <span class="bar" class:zero={!d.value} style:height="{(d.value / max) * 100}%"></span>
        {#if hover === i}<span class="tip" class:right={i > data.length * 0.7}><strong>{d.value} {unit}</strong> {d.label}</span>{/if}
      </button>
    {/each}
  </div>
  <div class="axis" aria-hidden="true">
    {#each data as d, i}<span>{i % tick === 0 ? d.short ?? d.label : ""}</span>{/each}
  </div>
  <details>
    <summary class="muted">Mostra come tabella</summary>
    <table>
      <thead><tr><th scope="col">{label}</th><th scope="col">Minuti</th></tr></thead>
      <tbody>{#each data as d}<tr><td>{d.label}</td><td>{d.value}</td></tr>{/each}</tbody>
    </table>
  </details>
</figure>

<style>
  .chart { margin: 0; }
  .plot { display: flex; align-items: end; gap: 2px; border-bottom: 1px solid var(--outline); }
  .col { position: relative; padding: 0; flex: 1; height: 100%; display: flex; align-items: end; cursor: default; outline-offset: 0; }
  .bar { width: 100%; background: var(--primary); border-radius: 4px 4px 0 0; min-height: 0; transition: height 0.6s var(--ease); }
  .bar.zero { background: transparent; }
  .col:hover .bar, .col:focus-visible .bar { background: var(--on-primary-container); }
  :global([data-theme="dark"]) .col:hover .bar { background: var(--on-bg); }
  .tip {
    position: absolute; bottom: calc(100% + 6px); left: 0; z-index: 2; white-space: nowrap; padding: 6px 10px; border-radius: var(--radius-xs);
    background: var(--on-bg); color: var(--bg); font-size: 0.82rem; pointer-events: none;
  }
  .tip.right { left: auto; right: 0; }
  .axis { display: flex; gap: 2px; margin-top: 6px; }
  .axis span { flex: 1; font-size: 0.72rem; color: var(--muted); white-space: nowrap; overflow: visible; }
  details { margin-top: 10px; font-size: 0.88rem; }
  summary { cursor: pointer; width: fit-content; }
  table { margin-top: 8px; border-collapse: collapse; }
  td, th { padding: 3px 14px 3px 0; text-align: left; font-variant-numeric: tabular-nums; }
  th { color: var(--muted); font-weight: 560; }
</style>
