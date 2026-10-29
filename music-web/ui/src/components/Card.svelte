<script>
  import Cover from "./Cover.svelte";
  import Icon from "./Icon.svelte";
  import { mdiPlay } from "../lib/icons.js";
  import { hrefOf, navigate, ui } from "../lib/state.svelte.js";
  import { player } from "../lib/player.svelte.js";
  let { item, width = 172 } = $props();
  let round = $derived(item.kind === "artist");
  let href = $derived(hrefOf(item));
  function open(e) {
    if (item.kind === "song") {
      e.preventDefault();
      player.playList([item]);
      return;
    }
    if (href) {
      e.preventDefault();
      navigate(href);
    }
  }
  function contextmenu(e) {
    e.preventDefault();
    ui.menu = { item, x: e.clientX, y: e.clientY };
  }
</script>

<a class="card" class:round href={href || "#"} onclick={open} oncontextmenu={contextmenu} style:width="{width}px">
  <span class="art">
    <Cover src={item.thumbnail} size={width * 2} shape={round ? "round" : "square"} radius="var(--radius-m)" alt="" />
    {#if item.kind === "song"}<span class="play"><Icon path={mdiPlay} size={26} /></span>{/if}
  </span>
  <span class="t clamp2">{item.title}</span>
  {#if item.subtitle && !round}<span class="s muted ellipsis">{item.subtitle}</span>{/if}
  {#if round}<span class="s muted">Artista</span>{/if}
</a>

<style>
  .card { display: flex; flex-direction: column; gap: 4px; flex: none; border-radius: var(--radius-m); }
  .art { position: relative; margin-bottom: 6px; transition: transform 0.3s var(--ease-spring); }
  .card:hover .art { transform: scale(1.02); }
  .card:active .art { transform: scale(0.97); }
  .t { font-weight: 640; line-height: 1.25; }
  .round { text-align: center; }
  .s { font-size: 0.85rem; }
  .play {
    position: absolute; right: 10px; bottom: 10px; width: 44px; height: 44px; border-radius: 50%;
    display: grid; place-items: center; background: var(--primary); color: var(--on-primary);
    opacity: 0; transform: translateY(6px); transition: 0.25s var(--ease);
  }
  .card:hover .play, .card:focus-visible .play { opacity: 1; transform: none; }
</style>
