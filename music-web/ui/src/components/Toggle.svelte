<script>
  // Interruttore Material 3 con etichetta e descrizione.
  let { checked = $bindable(false), label, hint = "", onchange } = $props();
  const id = "t" + Math.random().toString(36).slice(2, 8);
</script>

<label class="row" for={id}>
  <span class="txt"><span class="l">{label}</span>{#if hint}<span class="muted h">{hint}</span>{/if}</span>
  <input {id} type="checkbox" role="switch" bind:checked onchange={() => onchange?.(checked)} />
  <span class="sw" aria-hidden="true"><span class="knob"></span></span>
</label>

<style>
  .row { display: flex; align-items: center; gap: 16px; padding: 14px 16px; cursor: pointer; position: relative; }
  .txt { flex: 1; display: flex; flex-direction: column; }
  .l { font-weight: 600; }
  .h { font-size: 0.87rem; }
  input { position: absolute; opacity: 0; pointer-events: none; }
  .sw { width: 52px; height: 32px; border-radius: 16px; border: 2px solid var(--outline); background: var(--surface-3); position: relative; flex: none; transition: background 0.2s, border-color 0.2s; }
  .knob { position: absolute; top: 50%; left: 6px; width: 16px; height: 16px; border-radius: 50%; background: var(--faint); transform: translateY(-50%); transition: all 0.25s var(--ease-spring); }
  input:checked + .sw { background: var(--primary); border-color: var(--primary); }
  input:checked + .sw .knob { left: 22px; width: 24px; height: 24px; background: var(--on-primary); }
  input:focus-visible + .sw { outline: 3px solid var(--primary); outline-offset: 2px; }
</style>
