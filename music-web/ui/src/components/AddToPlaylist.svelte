<script>
  // Aggiungi brani a una playlist esistente o a una nuova.
  import Sheet from "./Sheet.svelte";
  import Icon from "./Icon.svelte";
  import Cover from "./Cover.svelte";
  import { mdiPlus } from "../lib/icons.js";
  import { ui, library, refreshPlaylists, toast } from "../lib/state.svelte.js";
  import { post } from "../lib/api.js";
  let items = $derived(ui.addTo || []);
  let creating = $state(false);
  let name = $state("");
  let busy = $state(false);
  function close() {
    ui.addTo = null;
  }
  async function add(p) {
    busy = true;
    try {
      await post("/api/playlists/" + p.id + "/items", { items });
      toast(items.length === 1 ? "Aggiunto a «" + p.name + "»" : items.length + " brani aggiunti a «" + p.name + "»");
      refreshPlaylists();
      close();
    } catch (e) {
      toast(e.message);
    } finally {
      busy = false;
    }
  }
  async function create(e) {
    e.preventDefault();
    if (!name.trim()) return;
    busy = true;
    try {
      await post("/api/playlists", { name: name.trim(), items });
      toast("Playlist «" + name.trim() + "» creata");
      await refreshPlaylists();
      close();
    } catch (e) {
      toast(e.message);
    } finally {
      busy = false;
    }
  }
</script>

<Sheet title={items.length === 1 ? "Aggiungi a playlist" : "Aggiungi " + items.length + " brani a playlist"} onclose={close}>
  {#if creating}
    <form class="new" onsubmit={create}>
      <label class="label muted" for="pl-name">Nome della playlist</label>
      <input id="pl-name" class="field" bind:value={name} maxlength="120" placeholder="Per esempio: Domenica mattina" />
      <div class="actions">
        <button type="button" class="btn text" onclick={() => (creating = false)}>Annulla</button>
        <button class="btn filled" disabled={busy || !name.trim()}>Crea e aggiungi</button>
      </div>
    </form>
  {:else}
    <button class="row newrow" onclick={() => (creating = true)}>
      <span class="plus"><Icon path={mdiPlus} /></span> Nuova playlist
    </button>
    <div class="group">
      {#each library.playlists as p (p.id)}
        <button class="row" disabled={busy} onclick={() => add(p)}>
          <Cover src={p.thumbnail} size={96} radius="var(--radius-xs)" />
          <span class="txt"><span class="ellipsis t">{p.name}</span><span class="muted s">{p.count} {p.count === 1 ? "brano" : "brani"}</span></span>
        </button>
      {/each}
    </div>
  {/if}
</Sheet>

<style>
  .row { display: flex; align-items: center; gap: 14px; width: 100%; padding: 8px 10px; text-align: left; }
  .row :global(.cover) { width: 48px; }
  .row:hover { background: var(--surface-3) !important; }
  .group .row { background: var(--surface-2); }
  .newrow { margin-bottom: 8px; font-weight: 640; border-radius: var(--radius-m); color: var(--primary); }
  .plus { width: 48px; height: 48px; border-radius: var(--radius-s); display: grid; place-items: center; background: var(--primary-container); color: var(--on-primary-container); }
  .txt { display: flex; flex-direction: column; min-width: 0; }
  .t { font-weight: 600; }
  .s { font-size: 0.85rem; }
  .new { display: flex; flex-direction: column; gap: 10px; padding: 4px 12px; }
  .actions { display: flex; justify-content: end; gap: 8px; margin-top: 6px; }
</style>
