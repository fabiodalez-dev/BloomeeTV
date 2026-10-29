<script>
  // Barra del lettore: completa su desktop, pillola compatta su mobile.
  import Cover from "./Cover.svelte";
  import Icon from "./Icon.svelte";
  import WavyProgress from "./WavyProgress.svelte";
  import SleepTimer from "./SleepTimer.svelte";
  import * as I from "../lib/icons.js";
  import { player } from "../lib/player.svelte.js";
  import { ui, isFavorite, toggleFavorite, navigate } from "../lib/state.svelte.js";
  import { artistNames } from "../lib/yt.js";
  import { time } from "../lib/format.js";
  let it = $derived(player.current);
  let sleepOpen = $state(false);
  let repeatIcon = $derived(player.repeat === "one" ? I.mdiRepeatOnce : player.repeat === "all" ? I.mdiRepeat : I.mdiRepeatOff);
  let volIcon = $derived(player.muted || player.volume === 0 ? I.mdiVolumeOff : player.volume < 0.5 ? I.mdiVolumeMedium : I.mdiVolumeHigh);
  function side(name) {
    ui.side = ui.side === name ? null : name;
  }
  function openArtist(e) {
    const a = it.artists && it.artists[0];
    if (a && a.id) {
      e.stopPropagation();
      navigate("/artist/" + a.id);
    }
  }
</script>

{#if it}
  <div class="bar" role="region" aria-label="Lettore">
    <div class="left">
      <button class="art" onclick={() => (ui.nowPlaying = true)} aria-label="Apri il lettore a schermo intero">
        <Cover src={it.thumbnail} size={120} radius="var(--radius-s)" />
      </button>
      <div class="meta">
        <button class="t ellipsis" onclick={() => (ui.nowPlaying = true)}>{it.title}</button>
        <button class="s ellipsis muted" onclick={openArtist}>{artistNames(it) || it.subtitle}</button>
      </div>
      <button class="icon-btn fav" class:on={isFavorite(it)} onclick={() => toggleFavorite(it)} aria-label={isFavorite(it) ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti"}>
        <Icon path={isFavorite(it) ? I.mdiHeart : I.mdiHeartOutline} />
      </button>
    </div>

    <div class="center">
      <div class="controls">
        <button class="icon-btn" class:on={player.shuffle} onclick={() => player.setShuffle(!player.shuffle)} aria-label="Casuale" aria-pressed={player.shuffle}><Icon path={I.mdiShuffleVariant} size={22} /></button>
        <button class="icon-btn" onclick={() => player.prev()} aria-label="Precedente"><Icon path={I.mdiSkipPrevious} size={28} /></button>
        <button class="play" class:loading={player.loading} onclick={() => player.toggle()} aria-label={player.playing ? "Pausa" : "Riproduci"}>
          <Icon path={player.playing ? I.mdiPause : I.mdiPlay} size={30} />
        </button>
        <button class="icon-btn" onclick={() => player.next()} aria-label="Successivo"><Icon path={I.mdiSkipNext} size={28} /></button>
        <button class="icon-btn" class:on={player.repeat !== "off"} onclick={() => player.cycleRepeat()} aria-label="Ripeti: {player.repeat === 'one' ? 'brano' : player.repeat === 'all' ? 'coda' : 'no'}"><Icon path={repeatIcon} size={22} /></button>
      </div>
      <div class="progress">
        <span class="tm">{time(player.time)}</span>
        <WavyProgress value={player.time} max={player.duration} buffered={player.buffered} playing={player.playing} onseek={(t) => player.seek(t)} height={26} />
        <span class="tm">{time(player.duration)}</span>
      </div>
    </div>

    <div class="right">
      <button class="icon-btn" class:on={ui.side === "lyrics"} onclick={() => side("lyrics")} aria-label="Testo" aria-pressed={ui.side === "lyrics"}><Icon path={I.mdiTextBoxOutline} size={22} /></button>
      <button class="icon-btn" class:on={ui.side === "queue"} onclick={() => side("queue")} aria-label="Coda" aria-pressed={ui.side === "queue"}><Icon path={I.mdiPlaylistPlay} size={24} /></button>
      <button class="icon-btn" class:on={!!player.sleep} onclick={() => (sleepOpen = true)} aria-label="Timer di spegnimento"><Icon path={I.mdiTimerOutline} size={22} /></button>
      <div class="vol">
        <button class="icon-btn" onclick={() => player.toggleMute()} aria-label={player.muted ? "Riattiva audio" : "Disattiva audio"}><Icon path={volIcon} size={22} /></button>
        <input type="range" min="0" max="1" step="0.01" value={player.muted ? 0 : player.volume} oninput={(e) => player.setVolume(+e.currentTarget.value)} aria-label="Volume" style:--v={(player.muted ? 0 : player.volume) * 100 + "%"} />
      </div>
    </div>

    <!-- Mobile: pillola -->
    <div class="mini" onclick={() => (ui.nowPlaying = true)} role="button" tabindex="0" onkeydown={(e) => e.key === "Enter" && (ui.nowPlaying = true)} aria-label="Apri il lettore">
      <span class="mini-art" class:spin={player.playing}><Cover src={it.thumbnail} size={96} shape="cookie" /></span>
      <span class="mini-meta"><span class="t ellipsis">{it.title}</span><span class="s ellipsis">{artistNames(it) || it.subtitle}</span></span>
      <button class="icon-btn" onclick={(e) => (e.stopPropagation(), toggleFavorite(it))} aria-label="Preferito"><Icon path={isFavorite(it) ? I.mdiHeart : I.mdiHeartOutline} size={22} /></button>
      <button class="icon-btn mini-play" onclick={(e) => (e.stopPropagation(), player.toggle())} aria-label={player.playing ? "Pausa" : "Riproduci"}><Icon path={player.playing ? I.mdiPause : I.mdiPlay} size={26} /></button>
      <span class="mini-prog" style:width={(player.duration ? (player.time / player.duration) * 100 : 0) + "%"}></span>
    </div>
  </div>
{/if}

{#if sleepOpen}<SleepTimer onclose={() => (sleepOpen = false)} />{/if}

<style>
  .bar {
    position: fixed; left: 0; right: 0; bottom: 0; z-index: 40; height: var(--bar);
    display: grid; grid-template-columns: minmax(0, 1fr) minmax(360px, 640px) minmax(0, 1fr); align-items: center; gap: 16px;
    padding: 0 16px; background: var(--glass); backdrop-filter: blur(24px) saturate(1.4); -webkit-backdrop-filter: blur(24px) saturate(1.4);
    border-top: 1px solid color-mix(in oklch, var(--outline) 50%, transparent);
  }
  .left { display: flex; align-items: center; gap: 12px; min-width: 0; }
  .art { width: 60px; flex: none; border-radius: var(--radius-s); transition: transform 0.25s var(--ease-spring); }
  .art:hover { transform: scale(1.05); }
  .meta { display: flex; flex-direction: column; min-width: 0; align-items: start; }
  .meta button { max-width: 100%; text-align: left; }
  .t { font-weight: 680; }
  .s { font-size: 0.86rem; }
  .meta .s:hover { text-decoration: underline; }
  .center { display: flex; flex-direction: column; align-items: stretch; gap: 0; }
  .controls { display: flex; justify-content: center; align-items: center; gap: 6px; }
  .play {
    width: 52px; height: 52px; border-radius: 18px; display: grid; place-items: center; background: var(--primary); color: var(--on-primary);
    transition: border-radius 0.35s var(--ease), transform 0.2s var(--ease-spring);
  }
  .play:hover { border-radius: 26px; }
  .play:active { transform: scale(0.92); }
  .play.loading { animation: breathe 1.2s ease-in-out infinite; }
  @keyframes breathe { 50% { border-radius: 26px; transform: scale(0.94); } }
  .progress { display: flex; align-items: center; gap: 10px; }
  .tm { font-size: 0.78rem; color: var(--muted); font-variant-numeric: tabular-nums; width: 40px; text-align: center; }
  .right { display: flex; align-items: center; justify-content: end; gap: 2px; }
  .vol { display: flex; align-items: center; }
  input[type="range"] { width: 110px; height: 22px; appearance: none; background: transparent; cursor: pointer; }
  input[type="range"]::-webkit-slider-runnable-track { height: 6px; border-radius: 3px; background: linear-gradient(90deg, var(--primary) var(--v), var(--surface-3) var(--v)); }
  input[type="range"]::-webkit-slider-thumb { appearance: none; width: 4px; height: 20px; margin-top: -7px; border-radius: 2px; background: var(--primary); }
  input[type="range"]::-moz-range-track { height: 6px; border-radius: 3px; background: var(--surface-3); }
  input[type="range"]::-moz-range-progress { height: 6px; border-radius: 3px; background: var(--primary); }
  input[type="range"]::-moz-range-thumb { width: 4px; height: 20px; border: 0; border-radius: 2px; background: var(--primary); }
  .mini { display: none; }

  @media (max-width: 1100px) { .vol input { display: none; } }
  @media (max-width: 860px) {
    .bar { left: 10px; right: 10px; bottom: calc(80px + var(--safe-b)); height: 64px; display: block; padding: 0; border: 0; border-radius: var(--radius-l); background: var(--primary-container); color: var(--on-primary-container); backdrop-filter: none; box-shadow: var(--shadow); overflow: hidden; }
    .left, .center, .right { display: none; }
    .mini { display: flex; align-items: center; gap: 10px; height: 100%; padding: 0 6px 0 8px; position: relative; cursor: pointer; }
    .mini-art { width: 48px; flex: none; }
    .mini-art.spin :global(.cover) { animation: spin 14s linear infinite; }
    .mini-meta { display: flex; flex-direction: column; min-width: 0; flex: 1; }
    .mini-meta .s { opacity: 0.8; }
    .mini-play { background: var(--on-primary-container); color: var(--primary-container); }
    .mini-prog { position: absolute; left: 0; bottom: 0; height: 3px; background: var(--on-primary-container); border-radius: 0 2px 2px 0; transition: width 0.3s linear; }
  }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
