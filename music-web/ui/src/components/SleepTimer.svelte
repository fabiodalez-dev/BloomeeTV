<script>
  import Sheet from "./Sheet.svelte";
  import { player } from "../lib/player.svelte.js";
  let { onclose } = $props();
  const options = [15, 30, 45, 60, 90];
  let left = $derived(player.sleep && player.sleep.until ? Math.max(1, Math.round((player.sleep.until - Date.now()) / 60000)) : null);
  function set(v) {
    player.setSleep(v);
    onclose();
  }
</script>

<Sheet title="Timer di spegnimento" {onclose}>
  <p class="muted note">
    {#if player.sleep && player.sleep.track}La musica si ferma alla fine di questo brano.
    {:else if left}La musica si ferma tra {left} min, con una sfumatura negli ultimi secondi.
    {:else}Ferma la musica dopo un po'. Gli ultimi 8 secondi sfumano.{/if}
  </p>
  <div class="opts">
    {#each options as m}<button class="chip" onclick={() => set(m)}>{m} min</button>{/each}
    <button class="chip" onclick={() => set("track")}>Fine del brano</button>
  </div>
  {#if player.sleep}<button class="btn tonal cancel" onclick={() => set(null)}>Annulla il timer</button>{/if}
</Sheet>

<style>
  .note { padding: 0 12px; margin: 0 0 14px; }
  .opts { display: flex; flex-wrap: wrap; gap: 8px; padding: 0 12px; }
  .cancel { margin: 18px 12px 4px; }
</style>
