<script>
  // Finestra modale: foglio dal basso su mobile, dialogo centrato su desktop.
  import { onMount } from "svelte";
  let { title, onclose, children, wide = false } = $props();
  let box;
  let opener = typeof document !== "undefined" ? document.activeElement : null;
  onMount(() => {
    box.querySelector("input, button, [tabindex]")?.focus();
    return () => opener && opener.focus && opener.focus();
  });
  function key(e) {
    if (e.key === "Escape") {
      e.stopPropagation();
      onclose();
    }
    if (e.key !== "Tab") return;
    const f = [...box.querySelectorAll("button, a[href], input, select, textarea, [tabindex]:not([tabindex='-1'])")].filter((x) => !x.disabled);
    if (!f.length) return;
    if (e.shiftKey && document.activeElement === f[0]) {
      e.preventDefault();
      f[f.length - 1].focus();
    } else if (!e.shiftKey && document.activeElement === f[f.length - 1]) {
      e.preventDefault();
      f[0].focus();
    }
  }
</script>

<svelte:window onkeydown={(e) => e.key === "Escape" && !box.contains(document.activeElement) && onclose()} />

<div class="scrim" onclick={onclose} role="presentation"></div>
<div class="sheet" class:wide bind:this={box} role="dialog" aria-modal="true" aria-label={title} tabindex="-1" onkeydown={key}>
  <span class="handle" aria-hidden="true"></span>
  {#if title}<h2 class="title head">{title}</h2>{/if}
  <div class="body">{@render children()}</div>
</div>

<style>
  .scrim { position: fixed; inset: 0; background: var(--scrim); z-index: 80; animation: fade 0.2s; }
  .sheet {
    position: fixed; z-index: 81; left: 50%; top: 50%; transform: translate(-50%, -50%);
    width: min(440px, calc(100vw - 32px)); max-height: min(80vh, 720px); display: flex; flex-direction: column;
    background: var(--surface); border-radius: var(--radius-l); box-shadow: var(--shadow); padding: 22px 0 12px;
    animation: pop 0.3s var(--ease-spring); outline: none;
  }
  .sheet.wide { width: min(640px, calc(100vw - 32px)); }
  .head { padding: 0 24px 12px; }
  .body { overflow: auto; padding: 0 12px; }
  .handle { display: none; }
  @keyframes pop { from { opacity: 0; transform: translate(-50%, -46%) scale(0.96); } }
  @keyframes fade { from { opacity: 0; } }
  @media (max-width: 640px) {
    .sheet, .sheet.wide { left: 0; right: 0; top: auto; bottom: 0; transform: none; width: auto; border-radius: var(--radius-l) var(--radius-l) 0 0; padding-bottom: calc(16px + var(--safe-b)); animation: up 0.32s var(--ease); max-height: 88vh; }
    .handle { display: block; width: 36px; height: 4px; border-radius: 2px; background: var(--outline); margin: -10px auto 14px; }
    @keyframes up { from { transform: translateY(100%); } }
  }
</style>
