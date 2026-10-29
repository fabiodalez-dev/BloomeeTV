<script>
  import { toasts, dismiss } from "../lib/state.svelte.js";
</script>

<div class="toasts" role="status" aria-live="polite">
  {#each toasts.items as t (t.id)}
    <div class="toast">
      <span>{t.message}</span>
      {#if t.action}<button class="btn text" onclick={() => (dismiss(t.id), t.action.run())}>{t.action.label}</button>{/if}
    </div>
  {/each}
</div>

<style>
  .toasts { position: fixed; z-index: 100; left: 50%; transform: translateX(-50%); bottom: calc(var(--bar) + 20px + var(--safe-b)); display: flex; flex-direction: column; gap: 8px; align-items: center; pointer-events: none; width: min(560px, calc(100vw - 24px)); }
  .toast {
    pointer-events: auto; display: flex; align-items: center; gap: 12px; min-height: 48px; padding: 6px 8px 6px 18px;
    border-radius: var(--radius-s); background: var(--on-bg); color: var(--bg); box-shadow: var(--shadow); font-weight: 520;
    animation: rise 0.3s var(--ease-spring);
  }
  .toast .btn.text { color: var(--primary-container); height: 36px; }
  @keyframes rise { from { opacity: 0; transform: translateY(12px) scale(0.98); } }
  @media (max-width: 860px) { .toasts { bottom: calc(150px + var(--safe-b)); } }
</style>
