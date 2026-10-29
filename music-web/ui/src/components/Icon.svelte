<script>
  // Icone Material Design (@mdi/js, Apache 2.0) come percorsi SVG.
  let { path, size = 24, label = null, class: cls = "" } = $props();
</script>

<svg class={cls} width={size} height={size} viewBox="0 0 24 24" aria-hidden={label ? undefined : "true"} role={label ? "img" : undefined} aria-label={label}>
  <path d={path} fill="currentColor" />
</svg>

<style>
  svg { flex: none; display: block; }
</style>
