<script>
  // Lettore a schermo intero: copertina a biscotto che gira piano mentre la
  // musica suona, onda di avanzamento, testo sincronizzato e coda accanto.
  import Cover from "./Cover.svelte";
  import Icon from "./Icon.svelte";
  import WavyProgress from "./WavyProgress.svelte";
  import Lyrics from "./Lyrics.svelte";
  import Queue from "./Queue.svelte";
  import SleepTimer from "./SleepTimer.svelte";
  import * as I from "../lib/icons.js";
  import { player } from "../lib/player.svelte.js";
  import { ui, settings, isFavorite, toggleFavorite, navigate } from "../lib/state.svelte.js";
  import { artistNames } from "../lib/yt.js";
  import { time, sized } from "../lib/format.js";
  import { lockScroll } from "../lib/scrollLock.js";
  import { onMount } from "svelte";
  onMount(lockScroll);
  let it = $derived(player.current);
  let sleepOpen = $state(false);
  let tab = $state("cover"); // mobile: cover | lyrics | queue
  let repeatIcon = $derived(player.repeat === "one" ? I.mdiRepeatOnce : player.repeat === "all" ? I.mdiRepeat : I.mdiRepeatOff);
  let startY = null;
  function close() {
    ui.nowPlaying = false;
  }
  function go(href) {
    close();
    navigate(href);
  }
  function key(e) {
    if (e.key === "Escape") close();
    if (e.target.closest("input, [role=slider]")) return;
    if (e.key === " ") {
      e.preventDefault();
      player.toggle();
    }
  }
  // Trascinare in giù la copertina chiude il lettore (mobile).
  function touchstart(e) {
    startY = e.touches[0].clientY;
  }
  function touchend(e) {
    if (startY != null && e.changedTouches[0].clientY - startY > 110) close();
    startY = null;
  }
</script>

<svelte:window onkeydown={key} />

{#if it}
  <div class="np" role="dialog" aria-modal="true" aria-label="In riproduzione: {it.title}">
    <div class="backdrop" style:background-image={it.thumbnail ? "url(" + sized(it.thumbnail, 120) + ")" : "none"} aria-hidden="true"></div>
    <header>
      <button class="icon-btn" onclick={close} aria-label="Chiudi il lettore"><Icon path={I.mdiChevronDown} size={30} /></button>
      <div class="from muted label ellipsis">{it.album ? it.album.name : "In riproduzione"}</div>
      <button class="icon-btn" onclick={(e) => { const r = e.currentTarget.getBoundingClientRect(); ui.menu = { item: it, x: r.right, y: r.bottom }; }} aria-label="Altre azioni"><Icon path={I.mdiDotsVertical} /></button>
    </header>

    <div class="layout" data-tab={tab}>
      <section class="stage" role="group" aria-label="Copertina e controlli" ontouchstart={touchstart} ontouchend={touchend}>
        <div class="disc" class:spin={settings.rotateCover} class:paused={!player.playing}>
          <Cover src={it.thumbnail} size={720} shape="cookie" alt="Copertina di {it.title}" />
        </div>
        <div class="info">
          <div class="txt">
            <h2 class="headline name">{it.title}</h2>
            <div class="artists">
              {#each it.artists.length ? it.artists : [{ name: it.subtitle, id: null }] as a, i}
                {#if i}<span class="muted">, </span>{/if}
                {#if a.id}<button class="artist" onclick={() => go("/artist/" + a.id)}>{a.name}</button>{:else}<span class="muted">{a.name}</span>{/if}
              {/each}
            </div>
          </div>
          <button class="icon-btn tonal fav" class:on={isFavorite(it)} onclick={() => toggleFavorite(it)} aria-label={isFavorite(it) ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti"}>
            <Icon path={isFavorite(it) ? I.mdiHeart : I.mdiHeartOutline} />
          </button>
          <button class="icon-btn tonal" onclick={() => (ui.addTo = [it])} aria-label="Aggiungi a playlist"><Icon path={I.mdiPlaylistPlus} /></button>
        </div>
        <div class="seek">
          <WavyProgress value={player.time} max={player.duration} buffered={player.buffered} playing={player.playing} onseek={(t) => player.seek(t)} height={36} />
          <div class="times"><span>{time(player.time)}</span><span>{time(player.duration)}</span></div>
        </div>
        {#if player.error}<p class="err"><Icon path={I.mdiAlertCircleOutline} size={18} /> {player.error}</p>{/if}
        <div class="controls">
          <button class="icon-btn" class:on={player.shuffle} onclick={() => player.setShuffle(!player.shuffle)} aria-label="Casuale" aria-pressed={player.shuffle}><Icon path={I.mdiShuffleVariant} /></button>
          <button class="side" onclick={() => player.prev()} aria-label="Precedente"><Icon path={I.mdiSkipPrevious} size={34} /></button>
          <button class="main" class:loading={player.loading} onclick={() => player.toggle()} aria-label={player.playing ? "Pausa" : "Riproduci"}>
            <Icon path={player.playing ? I.mdiPause : I.mdiPlay} size={42} />
          </button>
          <button class="side" onclick={() => player.next()} aria-label="Successivo"><Icon path={I.mdiSkipNext} size={34} /></button>
          <button class="icon-btn" class:on={player.repeat !== "off"} onclick={() => player.cycleRepeat()} aria-label="Ripeti"><Icon path={repeatIcon} /></button>
        </div>
        <div class="extras">
          <button class="chip" class:on={!!player.sleep} onclick={() => (sleepOpen = true)}><Icon path={I.mdiTimerOutline} size={18} /> {player.sleep ? (player.sleep.track ? "Fine brano" : "Timer attivo") : "Timer"}</button>
          <button class="chip" class:on={tab === "lyrics"} onclick={() => (tab = tab === "lyrics" ? "cover" : "lyrics")}><Icon path={I.mdiTextBoxOutline} size={18} /> Testo</button>
          <button class="chip" class:on={tab === "queue"} onclick={() => (tab = tab === "queue" ? "cover" : "queue")}><Icon path={I.mdiPlaylistPlay} size={18} /> Coda</button>
        </div>
      </section>

      <section class="panel">
        <div class="tabs" role="tablist">
          <button role="tab" aria-selected={ui.panel === "lyrics"} class="chip" class:on={ui.panel === "lyrics"} onclick={() => (ui.panel = "lyrics")}>Testo</button>
          <button role="tab" aria-selected={ui.panel === "queue"} class="chip" class:on={ui.panel === "queue"} onclick={() => (ui.panel = "queue")}>Coda</button>
        </div>
        <div class="panel-body">
          {#if (tab === "queue") || (tab === "cover" && ui.panel === "queue")}<Queue />{:else}<Lyrics big />{/if}
        </div>
      </section>
    </div>
  </div>
{/if}

{#if sleepOpen}<SleepTimer onclose={() => (sleepOpen = false)} />{/if}

<style>
  .np { position: fixed; inset: 0; z-index: 60; overscroll-behavior: contain; background: var(--bg); display: flex; flex-direction: column; animation: rise 0.42s var(--ease); overflow: hidden; }
  @keyframes rise { from { transform: translateY(100%); } }
  .backdrop {
    position: absolute; inset: -10%; background-size: cover; background-position: center; filter: blur(70px) saturate(1.5); opacity: 0.38;
    mask-image: radial-gradient(circle at 30% 30%, black, transparent 75%);
  }
  :global([data-theme="light"]) .backdrop { opacity: 0.28; }
  header { position: relative; display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 12px 16px 0; }
  .from { text-align: center; flex: 1; }
  .layout { position: relative; flex: 1; min-height: 0; display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: clamp(24px, 5vw, 80px); padding: 8px clamp(20px, 5vw, 80px) 24px; }
  .stage { display: flex; flex-direction: column; justify-content: center; gap: 18px; max-width: 560px; width: 100%; margin: 0 auto; min-height: 0; }
  .disc { width: min(100%, 52vh); align-self: center; filter: drop-shadow(0 24px 40px oklch(0.1 0.05 var(--seed-h) / 0.45)); }
  .disc.spin :global(.cover) { animation: spin 40s linear infinite; }
  .disc.paused :global(.cover) { animation-play-state: paused; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .info { display: flex; align-items: center; gap: 8px; }
  .txt { flex: 1; min-width: 0; }
  .name { font-size: clamp(1.5rem, 1.1rem + 1.5vw, 2.3rem); overflow: hidden; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
  .artists { margin-top: 6px; font-size: 1.05rem; color: var(--muted); }
  .artist { font-weight: 600; color: var(--on-bg); }
  .artist:hover { text-decoration: underline; }
  .times { display: flex; justify-content: space-between; font-size: 0.8rem; color: var(--muted); font-variant-numeric: tabular-nums; margin-top: 2px; }
  .err { display: flex; gap: 8px; align-items: center; color: var(--error); margin: 0; }
  .controls { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  .side { width: 72px; height: 64px; border-radius: 999px; display: grid; place-items: center; background: var(--surface-2); transition: transform 0.2s var(--ease-spring), border-radius 0.3s var(--ease); }
  .side:active { transform: scale(0.92); border-radius: var(--radius-m); }
  .main { width: 104px; height: 80px; border-radius: var(--radius-l); display: grid; place-items: center; background: var(--primary); color: var(--on-primary); transition: border-radius 0.4s var(--ease-spring), transform 0.2s var(--ease-spring); }
  .main:hover { border-radius: 40px; }
  .main:active { transform: scale(0.94); }
  .main.loading { animation: breathe 1.2s ease-in-out infinite; }
  @keyframes breathe { 50% { border-radius: 40px; transform: scale(0.95); } }
  .extras { display: flex; justify-content: center; gap: 8px; flex-wrap: wrap; }
  .extras .chip:nth-child(n + 2) { display: none; }
  .panel { display: flex; flex-direction: column; min-height: 0; }
  .tabs { display: flex; gap: 8px; padding: 4px 0 8px; }
  .panel-body { flex: 1; min-height: 0; overflow: auto; }

  @media (max-width: 900px) {
    .layout { grid-template-columns: 1fr; padding: 4px 20px calc(16px + var(--safe-b)); }
    .panel { display: none; }
    .extras .chip:nth-child(n + 2) { display: inline-flex; }
    .layout[data-tab="lyrics"] .panel, .layout[data-tab="queue"] .panel { display: flex; grid-row: 1; }
    .layout[data-tab="lyrics"] .stage, .layout[data-tab="queue"] .stage { grid-row: 2; justify-content: end; gap: 12px; }
    .layout[data-tab="lyrics"], .layout[data-tab="queue"] { grid-template-rows: minmax(0, 1fr) auto; }
    .layout[data-tab="lyrics"] .disc, .layout[data-tab="queue"] .disc, .layout[data-tab="lyrics"] .info, .layout[data-tab="queue"] .info { display: none; }
    .tabs { display: none; }
    .disc { width: min(100%, 44vh); }
  }
</style>
