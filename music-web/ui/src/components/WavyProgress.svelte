<script>
  // Barra di avanzamento ondulata (Material 3 Expressive): l'onda scorre
  // mentre la musica suona e si appiattisce in pausa.
  import { time as fmt } from "../lib/format.js";
  let { value = 0, max = 0, buffered = 0, playing = false, onseek, height = 32, label = "Posizione nel brano" } = $props();
  let width = $state(300);
  let drag = $state(null);
  let el;
  const WL = 34;
  let shown = $derived(drag != null ? drag : value);
  let p = $derived(max > 0 ? Math.min(1, Math.max(0, shown / max)) : 0);
  let x = $derived(p * width);
  let wave = $derived.by(() => {
    const mid = height / 2;
    let d = "M " + -WL + " " + mid;
    for (let i = -WL; i <= width + WL; i += 2) d += " L " + i + " " + (mid + Math.sin((i / WL) * Math.PI * 2) * 3.2).toFixed(2);
    return d;
  });
  function frac(e) {
    const r = el.getBoundingClientRect();
    return Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)) * max;
  }
  function down(e) {
    if (!max) return;
    el.setPointerCapture(e.pointerId);
    drag = frac(e);
  }
  function move(e) {
    if (drag != null) drag = frac(e);
  }
  function up(e) {
    if (drag == null) return;
    onseek?.(frac(e));
    drag = null;
  }
  function key(e) {
    const step = e.shiftKey ? 30 : 5;
    if (e.key === "ArrowRight") onseek?.(Math.min(max, value + step));
    else if (e.key === "ArrowLeft") onseek?.(Math.max(0, value - step));
    else return;
    e.preventDefault();
  }
</script>

<div
  class="wavy"
  class:playing={playing && drag == null}
  bind:this={el}
  bind:clientWidth={width}
  style:height="{height}px"
  role="slider"
  tabindex="0"
  aria-label={label}
  aria-valuemin="0"
  aria-valuemax={Math.round(max)}
  aria-valuenow={Math.round(shown)}
  aria-valuetext={fmt(shown) + " di " + fmt(max)}
  onpointerdown={down}
  onpointermove={move}
  onpointerup={up}
  onpointercancel={() => (drag = null)}
  onkeydown={key}
>
  <svg {width} {height} aria-hidden="true">
    <defs>
      <clipPath id="played-{width}"><rect x="0" y="0" width={Math.max(0, x - 5)} height={height} /></clipPath>
    </defs>
    <line class="rest" x1={Math.min(width, x + 6)} x2={width - 2} y1={height / 2} y2={height / 2} />
    {#if buffered > shown && max}
      <line class="buf" x1={Math.min(width, x + 6)} x2={Math.max(x + 6, (Math.min(buffered, max) / max) * width - 2)} y1={height / 2} y2={height / 2} />
    {/if}
    <circle class="end" cx={width - 2} cy={height / 2} r="2" />
    <g clip-path="url(#played-{width})">
      <g class="amp"><path class="wave" d={wave} /></g>
    </g>
  </svg>
  <span class="thumb" style:left="{x}px"></span>
</div>

<style>
  .wavy { position: relative; width: 100%; cursor: pointer; touch-action: none; border-radius: 8px; }
  svg { display: block; overflow: visible; }
  .rest { stroke: var(--surface-3); stroke-width: 4; stroke-linecap: round; }
  .buf { stroke: color-mix(in oklch, var(--primary) 28%, var(--surface-3)); stroke-width: 4; stroke-linecap: round; }
  .end { fill: var(--primary); }
  .wave { fill: none; stroke: var(--primary); stroke-width: 4; stroke-linecap: round; stroke-linejoin: round; }
  .amp { transform-box: fill-box; transform-origin: center; transform: scaleY(0.06); transition: transform 0.5s var(--ease); }
  .playing .amp { transform: scaleY(1); }
  .playing .wave { animation: flow 1.1s linear infinite; }
  @keyframes flow { to { transform: translateX(34px); } }
  .thumb {
    position: absolute; top: 50%; width: 5px; height: 22px; margin-left: -2.5px; transform: translateY(-50%);
    border-radius: 3px; background: var(--primary); transition: height 0.2s var(--ease);
  }
  .wavy:active .thumb, .wavy:focus-visible .thumb { height: 28px; }
</style>
