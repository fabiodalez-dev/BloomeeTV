<script>
  import { sized, snap } from "../lib/format.js";
  import Icon from "./Icon.svelte";
  import { mdiMusicNote } from "../lib/icons.js";
  // shape: square | round | cookie
  let { src, size = 226, alt = "", shape = "square", radius = "var(--radius-s)", class: cls = "" } = $props();
  // size è la misura per schermi ad alta densità; su quelli normali il
  // browser sceglie dallo srcset la metà. 0: misura richiesta, 1: URL
  // originale, 2: segnaposto.
  let failed = $state(0);
  let url = $derived(!src || failed > 1 ? null : failed ? src : sized(src, size));
  let small = $derived(src && !failed ? sized(src, size / 2) : null);
  let srcset = $derived(small && small !== url ? small + " " + snap(size / 2) + "w, " + url + " " + snap(size) + "w" : undefined);
</script>

<div class="cover {shape} {cls}" style:--r={radius}>
  {#if url}
    <img src={url} {srcset} sizes={srcset ? Math.round(size / 2) + "px" : undefined} {alt} loading="lazy" decoding="async" onerror={() => failed++} />
  {:else}
    <div class="ph"><Icon path={mdiMusicNote} size={28} /></div>
  {/if}
</div>

<style>
  .cover { position: relative; aspect-ratio: 1; overflow: hidden; background: var(--surface-2); border-radius: var(--r); flex: none; }
  .cover.round { border-radius: 50%; }
  .cover.cookie { border-radius: 0; clip-path: url(#cookie); }
  img { width: 100%; height: 100%; object-fit: cover; }
  .ph { position: absolute; inset: 0; display: grid; place-items: center; color: var(--faint); }
</style>
