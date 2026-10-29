<script>
  // Recap in stile Mochy: quanto hai ascoltato, chi e cosa, e quando.
  import Cover from "../components/Cover.svelte";
  import SongRow from "../components/SongRow.svelte";
  import BarChart from "../components/BarChart.svelte";
  import { get } from "../lib/api.js";
  import { navigate, toast } from "../lib/state.svelte.js";
  import { player } from "../lib/player.svelte.js";
  const RANGES = [["7", "7 giorni", 7], ["30", "30 giorni", 30], ["year", "Quest'anno", null], ["all", "Sempre", 0]];
  let range = $state("30");
  let st = $state(null);
  let error = $state("");
  function since(r) {
    const now = Date.now() / 1000;
    if (r === "all") return 0;
    if (r === "year") return new Date(new Date().getFullYear(), 0, 1).getTime() / 1000;
    return Math.floor(now - +r * 86400);
  }
  $effect(() => {
    const r = range;
    st = null;
    get("/api/stats?since=" + since(r)).then((d) => (st = d)).catch((e) => (error = e.message));
  });
  let hours = $derived(st ? st.hours.map((v, h) => ({ value: v, label: "ore " + h + ":00", short: h })) : []);
  let days = $derived(st ? st.days.slice(-60).map((d) => {
    const dt = new Date(d.day + "T12:00:00");
    return { value: d.minutes, label: dt.toLocaleDateString("it-IT", { weekday: "short", day: "numeric", month: "short" }), short: dt.getDate() + "/" + (dt.getMonth() + 1) };
  }) : []);
  let peak = $derived(st && st.minutes ? st.hours.indexOf(Math.max(...st.hours)) : null);
  let tracks = $derived(st ? st.tracks.map((t) => t.item) : []);
</script>

<div class="page">
  <h1 class="display">Recap</h1>
  <div class="scroll-x ranges" role="tablist">
    {#each RANGES as [k, label]}<button role="tab" aria-selected={range === k} class="chip" class:on={range === k} onclick={() => (range = k)}>{label}</button>{/each}
  </div>

  {#if error}
    <div class="empty"><p class="title">Il recap non si carica</p><p>{error}</p></div>
  {:else if !st}
    <span class="skeleton sk"></span>
  {:else if !st.plays}
    <div class="empty"><p class="title">Ancora niente da raccontare</p><p>Ascolta qualche brano per almeno 30 secondi e torna qui.</p></div>
  {:else}
    <section class="hero">
      <p class="big">{st.minutes.toLocaleString("it-IT")}</p>
      <p class="title">minuti di musica</p>
      <p class="muted facts">{st.plays} ascolti, {st.uniqueTracks} brani diversi, {st.uniqueArtists} artisti{#if peak != null}. Ascolti soprattutto verso le {peak}:00{/if}.</p>
    </section>

    {#if st.artists.length}
      <section>
        <div class="section-head"><h2 class="title">Artisti più ascoltati</h2></div>
        <ol class="artists">
          {#each st.artists.slice(0, 10) as a, i}
            <li class:first={i === 0}>
              <button onclick={() => a.id && navigate("/artist/" + a.id)} disabled={!a.id}>
                <span class="rank">{i + 1}</span>
                <Cover src={a.thumbnail} size={i === 0 ? 400 : 160} shape={i === 0 ? "cookie" : "round"} />
                <span class="an ellipsis">{a.name}</span>
                <span class="muted s">{Math.round(a.seconds / 60)} min</span>
              </button>
            </li>
          {/each}
        </ol>
      </section>
    {/if}

    <section>
      <div class="section-head"><h2 class="title">Brani più ascoltati</h2></div>
      <div class="group" role="list">
        {#each st.tracks.slice(0, 15) as t, i (t.item.videoId)}
          <SongRow item={t.item} number={i + 1} extra={t.plays + (t.plays === 1 ? " ascolto" : " ascolti") + " — " + (t.item.artists[0] ? t.item.artists[0].name : "")} onplay={() => player.playList(tracks, i)} />
        {/each}
      </div>
    </section>

    {#if st.albums.length}
      <section>
        <div class="section-head"><h2 class="title">Album</h2></div>
        <div class="scroll-x">
          {#each st.albums.slice(0, 12) as a}
            <button class="alb" onclick={() => a.id && navigate("/album/" + a.id)}>
              <Cover src={a.thumbnail} size={320} radius="var(--radius-m)" />
              <span class="an clamp2">{a.name}</span><span class="muted s">{a.artist || ""}</span>
            </button>
          {/each}
        </div>
      </section>
    {/if}

    <section class="charts">
      <div>
        <div class="section-head"><h2 class="title">Durante la giornata</h2></div>
        <BarChart data={hours} label="Minuti di ascolto per ora del giorno" tick={6} />
      </div>
      {#if days.length > 1}
        <div>
          <div class="section-head"><h2 class="title">Giorno per giorno</h2></div>
          <BarChart data={days} label="Minuti di ascolto per giorno" tick={Math.max(1, Math.ceil(days.length / 6))} />
        </div>
      {/if}
    </section>
  {/if}
</div>

<style>
  .ranges { gap: 8px; margin: 18px 0 8px; }
  .hero { padding: 28px 0 8px; }
  .big {
    margin: 0; font-size: clamp(4.5rem, 2rem + 12vw, 12rem); line-height: 0.85; font-weight: 900; font-stretch: 151%; letter-spacing: -0.05em;
    font-variation-settings: "opsz" 144; color: var(--primary); font-variant-numeric: tabular-nums;
  }
  .hero .title { font-size: 1.5rem; margin-top: 8px; }
  .facts { max-width: 60ch; margin: 8px 0 0; }
  .artists { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 20px 16px; align-items: end; }
  .artists li.first { grid-column: span 2; grid-row: span 2; }
  .artists button { display: flex; flex-direction: column; align-items: center; gap: 6px; width: 100%; text-align: center; position: relative; }
  .artists :global(.cover) { width: 100%; }
  .rank { position: absolute; left: 0; top: 0; z-index: 1; min-width: 30px; height: 30px; padding: 0 6px; border-radius: 15px; display: grid; place-items: center; background: var(--surface-3); font-weight: 760; font-size: 0.85rem; }
  .first .rank { background: var(--primary); color: var(--on-primary); min-width: 40px; height: 40px; border-radius: 20px; font-size: 1.1rem; }
  .an { font-weight: 680; max-width: 100%; }
  .first .an { font-size: 1.4rem; font-stretch: 125%; font-weight: 800; }
  .s { font-size: 0.85rem; }
  .alb { width: 160px; flex: none; display: flex; flex-direction: column; gap: 4px; text-align: left; }
  .alb :global(.cover) { margin-bottom: 6px; }
  .charts { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 380px), 1fr)); gap: 0 40px; }
  .sk { display: block; height: 300px; border-radius: var(--radius-l); margin-top: 20px; }
</style>
