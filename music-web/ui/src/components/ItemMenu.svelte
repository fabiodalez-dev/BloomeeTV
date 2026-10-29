<script>
  // Azioni su un elemento (brano, album, artista, playlist): menu vicino al
  // punto toccato su desktop, foglio dal basso su mobile.
  import Sheet from "./Sheet.svelte";
  import Icon from "./Icon.svelte";
  import Cover from "./Cover.svelte";
  import * as I from "../lib/icons.js";
  import { ui, toggleFavorite, isFavorite, navigate, hrefOf, toast } from "../lib/state.svelte.js";
  import { player } from "../lib/player.svelte.js";
  import { artistNames } from "../lib/yt.js";
  let m = $derived(ui.menu);
  let it = $derived(m.item);
  let song = $derived(it.kind === "song");
  let mobile = $state(typeof matchMedia !== "undefined" && matchMedia("(max-width: 640px)").matches);
  let pos = $derived.by(() => {
    const w = 280, h = 420;
    return { left: Math.max(8, Math.min(m.x - w, innerWidth - w - 8)), top: Math.max(8, Math.min(m.y, innerHeight - h - 8)) };
  });
  function close() {
    ui.menu = null;
  }
  function act(f) {
    return () => {
      close();
      f();
    };
  }
  let actions = $derived([
    song && { icon: I.mdiPlaylistPlay, label: "Riproduci dopo", run: () => player.playNext(it) },
    song && { icon: I.mdiQueueFirstInLastOut, label: "Aggiungi alla coda", run: () => player.enqueue(it) },
    song && { icon: I.mdiRadio, label: "Avvia radio", run: () => player.startRadio(it) },
    song && { icon: I.mdiPlaylistPlus, label: "Aggiungi a playlist", run: () => (ui.addTo = [it]) },
    { icon: isFavorite(it) ? I.mdiHeart : I.mdiHeartOutline, label: isFavorite(it) ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti", run: () => toggleFavorite(it) },
    m.context && m.context.removeLabel && { icon: I.mdiPlaylistRemove, label: m.context.removeLabel, run: m.context.remove },
    song && it.artists && it.artists[0] && it.artists[0].id && { icon: I.mdiAccountMusic, label: "Vai all'artista", run: () => navigate("/artist/" + it.artists[0].id) },
    song && it.album && it.album.id && { icon: I.mdiAlbum, label: "Vai all'album", run: () => navigate("/album/" + it.album.id) },
    !song && hrefOf(it) && { icon: I.mdiChevronRight, label: "Apri", run: () => navigate(hrefOf(it)) },
    { icon: I.mdiLinkVariant, label: "Copia link YouTube Music", run: copy }
  ].filter(Boolean));
  function copy() {
    const url = it.videoId ? "https://music.youtube.com/watch?v=" + it.videoId : it.kind === "artist" ? "https://music.youtube.com/channel/" + it.browseId : "https://music.youtube.com/browse/" + it.browseId;
    navigator.clipboard.writeText(url).then(() => toast("Link copiato"), () => toast("Impossibile copiare il link"));
  }
  function key(e) {
    if (e.key === "Escape") close();
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const b = [...e.currentTarget.querySelectorAll("button")];
      const i = b.indexOf(document.activeElement);
      b[(i + (e.key === "ArrowDown" ? 1 : -1) + b.length) % b.length].focus();
    }
  }
</script>

{#snippet list()}
  <div class="head">
    <Cover src={it.thumbnail} size={96} shape={it.kind === "artist" ? "round" : "square"} radius="var(--radius-xs)" />
    <div class="ht"><div class="ellipsis t">{it.title}</div><div class="ellipsis muted s">{artistNames(it) || it.subtitle}</div></div>
  </div>
  {#each actions as a}
    <button class="item" onclick={act(a.run)}><Icon path={a.icon} size={22} /> {a.label}</button>
  {/each}
{/snippet}

{#if mobile}
  <Sheet title="" onclose={close}>{@render list()}</Sheet>
{:else}
  <div class="catch" onclick={close} oncontextmenu={(e) => (e.preventDefault(), close())} role="presentation"></div>
  <div class="menu" role="menu" tabindex="-1" style:left="{pos.left}px" style:top="{pos.top}px" onkeydown={key} {@attach (n) => n.querySelector("button")?.focus()}>
    {@render list()}
  </div>
{/if}

<style>
  .catch { position: fixed; inset: 0; z-index: 90; }
  .menu {
    position: fixed; z-index: 91; width: 280px; padding: 8px; border-radius: var(--radius-m);
    background: var(--surface-2); box-shadow: var(--shadow); animation: in 0.18s var(--ease); transform-origin: top right;
  }
  @keyframes in { from { opacity: 0; transform: scale(0.94); } }
  .head { display: flex; gap: 12px; align-items: center; padding: 6px 8px 12px; border-bottom: 1px solid var(--outline); margin-bottom: 6px; }
  .head :global(.cover) { width: 44px; }
  .ht { min-width: 0; }
  .t { font-weight: 640; }
  .s { font-size: 0.85rem; }
  .item { display: flex; align-items: center; gap: 14px; width: 100%; padding: 11px 12px; border-radius: var(--radius-s); text-align: left; font-weight: 520; }
  .item:hover, .item:focus-visible { background: color-mix(in oklch, var(--on-bg) 8%, transparent); outline: none; }
</style>
