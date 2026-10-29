<script>
  import Cover from "./Cover.svelte";
  import Icon from "./Icon.svelte";
  import { mdiDotsVertical, mdiHeart, mdiPlay } from "../lib/icons.js";
  import { artistNames } from "../lib/yt.js";
  import { time } from "../lib/format.js";
  import { isFavorite, ui, navigate } from "../lib/state.svelte.js";
  import { player } from "../lib/player.svelte.js";
  // number: posizione nell'album al posto della copertina.
  let { item, onplay, number = null, context = null, extra = null } = $props();
  let current = $derived(player.current && player.current.videoId === item.videoId);
  function menu(e) {
    e.stopPropagation();
    const r = e.currentTarget.getBoundingClientRect();
    ui.menu = { item, x: r.right, y: r.bottom, context };
  }
  function contextmenu(e) {
    e.preventDefault();
    ui.menu = { item, x: e.clientX, y: e.clientY, context };
  }
</script>

<div class="row" class:current role="listitem" oncontextmenu={contextmenu}>
  <button class="main" onclick={onplay} aria-label={"Riproduci " + item.title}>
    {#if number != null}
      <span class="num">{#if current}<span class="eq" class:paused={!player.playing}><i></i><i></i><i></i></span>{:else}{number}{/if}</span>
    {:else}
      <span class="art">
        <Cover src={item.thumbnail} size={96} radius="var(--radius-xs)" />
        {#if current}<span class="playing-badge"><span class="eq" class:paused={!player.playing}><i></i><i></i><i></i></span></span>{/if}
      </span>
    {/if}
    <span class="text">
      <span class="t ellipsis">{item.title}</span>
      <span class="s ellipsis muted">
        {#if isFavorite(item)}<Icon path={mdiHeart} size={13} class="fav" />{/if}
        {extra ?? (artistNames(item) || item.subtitle)}
      </span>
    </span>
  </button>
  {#if item.duration}<span class="dur muted">{time(item.duration)}</span>{/if}
  <button class="icon-btn more" onclick={menu} aria-label="Altre azioni per {item.title}"><Icon path={mdiDotsVertical} /></button>
</div>

<style>
  .row { display: flex; align-items: center; gap: 4px; padding: 6px 6px 6px 8px; min-height: 64px; transition: background 0.15s; }
  .row:hover { background: var(--surface-2) !important; }
  .main { display: flex; align-items: center; gap: 14px; flex: 1; min-width: 0; text-align: left; border-radius: var(--radius-xs); }
  .art { position: relative; width: 48px; flex: none; }
  .num { width: 32px; text-align: center; font-weight: 600; color: var(--muted); font-variant-numeric: tabular-nums; flex: none; display: grid; place-items: center; }
  .text { display: flex; flex-direction: column; min-width: 0; }
  .t { font-weight: 600; }
  .current .t { color: var(--primary); }
  .s { font-size: 0.87rem; display: flex; align-items: center; gap: 4px; }
  .s :global(.fav) { color: var(--primary); }
  .dur { font-size: 0.85rem; font-variant-numeric: tabular-nums; padding: 0 6px; }
  .playing-badge { position: absolute; inset: 0; display: grid; place-items: center; background: oklch(0 0 0 / 0.45); border-radius: var(--radius-xs); color: white; }
  .eq { display: inline-flex; align-items: end; gap: 2px; height: 14px; }
  .eq i { width: 3px; background: currentColor; border-radius: 2px; animation: bar 0.9s ease-in-out infinite; }
  .num .eq { color: var(--primary); }
  .eq i:nth-child(2) { animation-delay: -0.3s; }
  .eq i:nth-child(3) { animation-delay: -0.6s; }
  .eq.paused i { animation-play-state: paused; }
  @keyframes bar { 0%, 100% { height: 4px; } 50% { height: 14px; } }
  @media (max-width: 640px) { .dur { display: none; } }
</style>
