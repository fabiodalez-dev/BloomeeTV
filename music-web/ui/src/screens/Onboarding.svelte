<script>
  // Primo avvio, come l'onboarding di Mochy: benvenuto, profilo, aspetto,
  // account YouTube Music, cosa importare, artisti preferiti, ultime scelte.
  import { onMount } from "svelte";
  import Icon from "../components/Icon.svelte";
  import Cover from "../components/Cover.svelte";
  import YouTubeConnect from "../components/YouTubeConnect.svelte";
  import * as I from "../lib/icons.js";
  import { yt, ytAll, post, patch, put } from "../lib/api.js";
  import { flatItems, continuation, parseSections, searchPage, searchParams } from "../lib/yt.js";
  import { session, settings, library, loadLibrary, saveSettings, toast } from "../lib/state.svelte.js";

  const STEPS = ["welcome", "profile", "look", "youtube", "import", "artists", "last"];
  let step = $state(0);
  let name = $derived(STEPS[step]);
  let displayName = $state(session.user.displayName);

  // Importazione
  let sources = $state(null); // [{ id, title, kind, thumbnail, count?, browseId }]
  let picked = $state(new Set());
  let importing = $state(null); // { done, total, label }

  // Artisti
  let suggested = $state([]);
  let chosen = $state(new Map());
  let q = $state("");
  let found = $state([]);
  let timer;

  function next() {
    // Senza account collegato il passaggio di importazione non serve.
    let n = step + 1;
    if (STEPS[n] === "import" && !session.youtube) n++;
    step = Math.min(n, STEPS.length - 1);
  }
  function back() {
    let n = step - 1;
    if (STEPS[n] === "import" && !session.youtube) n--;
    step = Math.max(0, n);
  }

  async function saveProfile() {
    const v = displayName.trim();
    if (v && v !== session.user.displayName) {
      try {
        await patch("/api/profile", { displayName: v });
        session.user.displayName = v;
      } catch (e) {
        toast(e.message);
        return;
      }
    }
    next();
  }

  function setTheme(k) {
    settings.theme = k;
    saveSettings();
  }

  $effect(() => {
    if (name === "import" && session.youtube && !sources) loadSources();
    if (name === "artists" && !suggested.length) loadSuggested();
  });

  async function loadSources() {
    const out = [{ id: "liked", kind: "liked", title: "Brani che ti piacciono", thumbnail: null, browseId: "VLLM" }];
    try {
      const [pl, al, ar] = await Promise.all(
        ["FEmusic_liked_playlists", "FEmusic_liked_albums", "FEmusic_library_corpus_artists"].map((b) => yt("browse", { browseId: b, personal: true }).catch(() => null))
      );
      const lists = pl ? flatItems(pl).filter((i) => i.browseId && i.browseId !== "VLLM" && /^(VL|PL)/.test(i.browseId)) : [];
      lists.forEach((p) => out.push({ id: p.browseId, kind: "playlist", title: p.title, thumbnail: p.thumbnail, browseId: p.browseId, subtitle: p.subtitle }));
      const albums = al ? flatItems(al).filter((i) => i.kind === "album") : [];
      const artists = ar ? flatItems(ar).filter((i) => i.kind === "artist") : [];
      if (albums.length) out.push({ id: "albums", kind: "albums", title: "Album salvati", subtitle: albums.length + " album", items: albums, thumbnail: albums[0].thumbnail });
      if (artists.length) out.push({ id: "artists", kind: "artists", title: "Artisti che segui", subtitle: artists.length + " artisti", items: artists, thumbnail: artists[0].thumbnail });
    } catch (e) {
      toast(e.message);
    }
    sources = out;
    picked = new Set(out.filter((s) => s.kind !== "playlist").map((s) => s.id));
  }

  function toggle(id) {
    const s = new Set(picked);
    s.has(id) ? s.delete(id) : s.add(id);
    picked = s;
  }

  async function runImport() {
    const todo = sources.filter((s) => picked.has(s.id));
    importing = { done: 0, total: todo.length, label: "" };
    let favs = 0, lists = 0;
    for (const s of todo) {
      importing.label = s.title;
      try {
        if (s.kind === "liked" || s.kind === "playlist") {
          const { items } = await ytAll("browse", { browseId: s.browseId, personal: true }, (d) => flatItems(d).filter((i) => i.videoId), continuation, 60);
          const songs = items.map((i) => ({ ...i, kind: "song" }));
          if (s.kind === "liked") favs += (await post("/api/favorites/batch", { items: songs })).added;
          else if (songs.length) {
            await post("/api/playlists", { name: s.title, description: "Importata da YouTube Music", items: songs.slice(0, 5000) });
            lists++;
          }
        } else {
          favs += (await post("/api/favorites/batch", { items: s.items })).added;
        }
      } catch (e) {
        toast(s.title + ": " + e.message);
      }
      importing.done++;
    }
    await loadLibrary();
    importing = null;
    const parts = [favs && favs + " preferiti", lists && lists + " playlist"].filter(Boolean);
    toast(parts.length ? "Importati " + parts.join(" e ") : "Niente di nuovo da importare");
    next();
  }

  async function loadSuggested() {
    try {
      const d = await yt("browse", { browseId: "FEmusic_charts" });
      const seen = new Set(library.favorites.filter((f) => f.kind === "artist").map((f) => f.browseId));
      suggested = parseSections(d).flatMap((s) => s.items).filter((i) => i.kind === "artist" && !seen.has(i.browseId)).slice(0, 18);
    } catch {}
  }

  function search() {
    clearTimeout(timer);
    const text = q.trim();
    if (!text) return (found = []);
    timer = setTimeout(async () => {
      try {
        const d = await yt("search", { query: text, params: searchParams.artist });
        if (q.trim() === text) found = searchPage(d).items.filter((i) => i.kind === "artist").slice(0, 12);
      } catch {}
    }, 300);
  }

  function pick(a) {
    const m = new Map(chosen);
    m.has(a.browseId) ? m.delete(a.browseId) : m.set(a.browseId, a);
    chosen = m;
  }

  async function saveArtists() {
    if (chosen.size) {
      try {
        await post("/api/favorites/batch", { items: [...chosen.values()].map((a) => ({ ...a, kind: "artist" })) });
        await loadLibrary();
      } catch (e) {
        toast(e.message);
      }
    }
    next();
  }

  async function finish() {
    settings.onboarded = true;
    try {
      await put("/api/state/settings", { data: $state.snapshot(settings) });
    } catch (e) {
      toast(e.message);
    }
  }

  onMount(() => {
    document.getElementById("onb")?.focus();
  });
  let artistsShown = $derived(q.trim() ? found : suggested);
</script>

<div class="onb" id="onb" tabindex="-1" role="dialog" aria-modal="true" aria-label="Configurazione iniziale">
  <div class="progress" aria-hidden="true">
    {#each STEPS as s, i}{#if s !== "import" || session.youtube}<span class:on={i <= step}></span>{/if}{/each}
  </div>

  {#key step}
    <section class="page" class:welcome={name === "welcome"}>
      {#if name === "welcome"}
        <div class="shapes" aria-hidden="true"><span class="c1"></span><span class="c2"></span><span class="c3"></span></div>
        <h1 class="hello">Ciao,<br />{session.user.displayName}</h1>
        <p class="lead">Un modo tutto tuo per ascoltare: testi che scorrono a tempo, playlist che restano tue, colori che cambiano con la musica.</p>
        <div class="actions"><button class="btn filled big" onclick={next}>Cominciamo</button></div>
      {:else if name === "profile"}
        <span class="badge"><Icon path={I.mdiAccountCircle} size={30} /></span>
        <h2 class="headline">Come ti chiami?</h2>
        <p class="lead">È il nome con cui ti saluta la Home. Puoi cambiarlo quando vuoi.</p>
        <form onsubmit={(e) => (e.preventDefault(), saveProfile())}>
          <input class="field big-field" bind:value={displayName} maxlength="64" aria-label="Il tuo nome" />
          <div class="actions"><button type="button" class="btn text" onclick={back}>Indietro</button><button class="btn filled big" disabled={!displayName.trim()}>Avanti</button></div>
        </form>
      {:else if name === "look"}
        <span class="badge"><Icon path={I.mdiThemeLightDark} size={30} /></span>
        <h2 class="headline">Chiaro o scuro?</h2>
        <p class="lead">I colori dell'interfaccia seguono la copertina del brano in ascolto, in tutti e due i temi.</p>
        <div class="themes">
          {#each [["auto", "Come il sistema", I.mdiThemeLightDark], ["light", "Chiaro", I.mdiWhiteBalanceSunny], ["dark", "Scuro", I.mdiWeatherNight]] as [k, label, icon]}
            <button class="theme {k}" class:on={settings.theme === k} aria-pressed={settings.theme === k} onclick={() => setTheme(k)}>
              <span class="preview" aria-hidden="true"><i></i><i></i><i></i></span>
              <span class="tl"><Icon path={icon} size={18} /> {label}</span>
            </button>
          {/each}
        </div>
        <label class="check"><input type="checkbox" bind:checked={settings.dynamicColor} onchange={saveSettings} /> Colori dalla copertina in ascolto</label>
        <div class="actions"><button class="btn text" onclick={back}>Indietro</button><button class="btn filled big" onclick={next}>Avanti</button></div>
      {:else if name === "youtube"}
        <span class="badge yt"><Icon path={I.mdiYoutube} size={30} /></span>
        <h2 class="headline">Il tuo YouTube Music</h2>
        <p class="lead">Facoltativo. Collegandolo hai la Home personale e puoi importare le tue playlist e i brani che ti piacciono. Senza, cerchi e ascolti lo stesso.</p>
        <div class="panel"><YouTubeConnect onconnected={() => setTimeout(next, 900)} /></div>
        <div class="actions"><button class="btn text" onclick={back}>Indietro</button><button class="btn tonal big" onclick={next}>{session.youtube ? "Avanti" : "Salta"}</button></div>
      {:else if name === "import"}
        <span class="badge"><Icon path={I.mdiImport} size={30} /></span>
        <h2 class="headline">Cosa porti con te?</h2>
        <p class="lead">Le playlist diventano tue copie qui: puoi modificarle senza toccare quelle di YouTube.</p>
        {#if importing}
          <div class="importing" role="status">
            <div class="bar"><span style:width={(importing.done / Math.max(1, importing.total)) * 100 + "%"}></span></div>
            <p>Importo «{importing.label}» ({importing.done + 1} di {importing.total})…</p>
          </div>
        {:else if !sources}
          <p class="muted">Leggo la tua libreria di YouTube Music…</p>
        {:else}
          <div class="sources">
            {#each sources as s (s.id)}
              <button class="src" class:on={picked.has(s.id)} aria-pressed={picked.has(s.id)} onclick={() => toggle(s.id)}>
                {#if s.kind === "liked"}<span class="liked"><Icon path={I.mdiHeart} size={26} /></span>{:else}<Cover src={s.thumbnail} size={120} shape={s.kind === "artists" ? "round" : "square"} radius="var(--radius-xs)" />{/if}
                <span class="st"><span class="ellipsis t">{s.title}</span>{#if s.subtitle}<span class="muted s ellipsis">{s.subtitle}</span>{/if}</span>
                <span class="tick" aria-hidden="true">{#if picked.has(s.id)}<Icon path={I.mdiCheck} size={20} />{/if}</span>
              </button>
            {/each}
          </div>
          <div class="actions">
            <button class="btn text" onclick={next}>Salta</button>
            <button class="btn filled big" disabled={!picked.size} onclick={runImport}>Importa {picked.size ? "(" + picked.size + ")" : ""}</button>
          </div>
        {/if}
      {:else if name === "artists"}
        <span class="badge"><Icon path={I.mdiAccountMusic} size={30} /></span>
        <h2 class="headline">Chi ascolti di più?</h2>
        <p class="lead">Scegli qualche artista: li ritrovi in Home e nella Libreria.</p>
        <input class="field" bind:value={q} oninput={search} placeholder="Cerca un artista" aria-label="Cerca un artista" />
        <div class="bubbles">
          {#each artistsShown as a (a.browseId)}
            <button class="bubble" class:on={chosen.has(a.browseId)} aria-pressed={chosen.has(a.browseId)} onclick={() => pick(a)}>
              <span class="ph"><Cover src={a.thumbnail} size={226} shape="round" />{#if chosen.has(a.browseId)}<span class="ok"><Icon path={I.mdiCheck} size={22} /></span>{/if}</span>
              <span class="an clamp2">{a.title}</span>
            </button>
          {/each}
        </div>
        <div class="actions"><button class="btn text" onclick={back}>Indietro</button><button class="btn filled big" onclick={saveArtists}>{chosen.size ? "Avanti con " + chosen.size : "Avanti"}</button></div>
      {:else if name === "last"}
        <span class="badge"><Icon path={I.mdiPlaylistPlay} size={30} /></span>
        <h2 class="headline">Ultima cosa</h2>
        <p class="lead">Come vuoi che continui la musica? Puoi cambiarlo in Impostazioni.</p>
        <div class="panel opts">
          <label class="check"><input type="checkbox" bind:checked={settings.autoplay} onchange={saveSettings} /> <span><strong>Riproduzione automatica</strong><br /><span class="muted">Finita la coda, continua con brani simili</span></span></label>
          <div class="xf">
            <span><strong>Crossfade</strong><br /><span class="muted">Sfuma un brano nel successivo</span></span>
            <div class="chips">{#each [0, 4, 8] as s}<button class="chip" class:on={settings.crossfade === s} onclick={() => ((settings.crossfade = s), saveSettings())}>{s ? s + " s" : "No"}</button>{/each}</div>
          </div>
        </div>
        <div class="actions"><button class="btn text" onclick={back}>Indietro</button><button class="btn filled big" onclick={finish}>Inizia ad ascoltare</button></div>
      {/if}
    </section>
  {/key}
</div>

<style>
  .onb { position: fixed; inset: 0; z-index: 70; background: var(--bg); overflow-y: auto; outline: none; display: flex; flex-direction: column; }
  .progress { display: flex; gap: 6px; padding: 18px clamp(16px, 4vw, 48px) 0; max-width: 760px; width: 100%; margin: 0 auto; }
  .progress span { flex: 1; height: 4px; border-radius: 2px; background: var(--surface-3); transition: background 0.4s; }
  .progress span.on { background: var(--primary); }
  .page { position: relative; width: 100%; max-width: 760px; margin: 0 auto; padding: clamp(28px, 6vh, 64px) clamp(16px, 4vw, 48px) 40px; animation: enter 0.45s var(--ease); flex: 1; display: flex; flex-direction: column; }
  @keyframes enter { from { opacity: 0; transform: translateX(24px); } }
  .welcome { justify-content: center; }
  .shapes { position: relative; height: clamp(180px, 36vh, 360px); margin-bottom: 28px; }
  .shapes span { position: absolute; clip-path: url(#cookie); animation: turn 50s linear infinite; }
  .c1 { width: min(36vh, 340px); aspect-ratio: 1; right: 0; top: 0; background: var(--primary); }
  .c2 { width: min(17vh, 160px); aspect-ratio: 1; left: 0; bottom: 0; background: var(--tertiary); animation-direction: reverse !important; }
  .c3 { width: min(10vh, 90px); aspect-ratio: 1; left: 34%; top: 14%; background: var(--primary-container); }
  .welcome .actions { margin-top: 0; }
  @keyframes turn { to { transform: rotate(360deg); } }
  .hello { position: relative; margin: 0; font-size: clamp(3.4rem, 2rem + 7vw, 7.5rem); line-height: 0.86; font-weight: 900; font-stretch: 151%; letter-spacing: -0.045em; font-variation-settings: "opsz" 144; }
  .lead { color: var(--muted); font-size: 1.1rem; max-width: 52ch; margin: 14px 0 24px; position: relative; }
  .badge { width: 60px; height: 60px; border-radius: var(--radius-m); display: grid; place-items: center; background: var(--primary-container); color: var(--on-primary-container); margin-bottom: 18px; }
  .badge.yt { background: #ff000022; color: #e22; }
  .actions { display: flex; justify-content: space-between; align-items: center; gap: 12px; margin-top: auto; padding-top: 28px; position: relative; }
  .welcome .actions { justify-content: start; }
  .big-field { height: 64px; font-size: 1.4rem; font-weight: 600; }
  .panel { background: var(--surface); border-radius: var(--radius-l); padding: 20px; }
  .themes { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
  .theme { display: flex; flex-direction: column; gap: 10px; padding: 10px; border-radius: var(--radius-m); border: 2px solid var(--outline); text-align: left; transition: border-color 0.2s, border-radius 0.3s var(--ease); }
  .theme.on { border-color: var(--primary); border-radius: var(--radius-l); }
  .preview { aspect-ratio: 4 / 3; border-radius: var(--radius-s); display: flex; flex-direction: column; justify-content: end; gap: 5px; padding: 10px; background: #f3f6f1; overflow: hidden; }
  .preview i { display: block; height: 8px; border-radius: 4px; background: #c9d8c7; }
  .preview i:first-child { width: 40%; height: 26px; border-radius: 8px; background: #3d6b42; }
  .theme.dark .preview { background: #18201a; }
  .theme.dark .preview i { background: #2e3a30; }
  .theme.dark .preview i:first-child { background: #9fd4a2; }
  .theme.auto .preview { background: linear-gradient(135deg, #f3f6f1 50%, #18201a 50%); }
  .tl { display: flex; align-items: center; gap: 6px; font-weight: 600; }
  .check { display: flex; align-items: start; gap: 12px; margin-top: 18px; cursor: pointer; }
  .check input { width: 20px; height: 20px; accent-color: var(--primary); margin-top: 2px; flex: none; }
  .opts .check { margin-top: 0; }
  .xf { display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap; margin-top: 18px; padding-top: 18px; border-top: 1px solid var(--outline); }
  .chips { display: flex; gap: 6px; }
  .sources { display: flex; flex-direction: column; gap: 3px; }
  .src { display: flex; align-items: center; gap: 14px; padding: 8px 14px 8px 8px; background: var(--surface); border-radius: var(--radius-xs); text-align: left; }
  .src:first-child { border-radius: var(--radius-m) var(--radius-m) var(--radius-xs) var(--radius-xs); }
  .src:last-child { border-radius: var(--radius-xs) var(--radius-xs) var(--radius-m) var(--radius-m); }
  .src :global(.cover) { width: 52px; }
  .liked { width: 52px; height: 52px; border-radius: var(--radius-xs); display: grid; place-items: center; background: var(--primary); color: var(--on-primary); flex: none; }
  .st { flex: 1; min-width: 0; display: flex; flex-direction: column; }
  .t { font-weight: 640; }
  .s { font-size: 0.87rem; }
  .tick { width: 28px; height: 28px; border-radius: 50%; border: 2px solid var(--outline); display: grid; place-items: center; flex: none; transition: 0.2s; }
  .src.on .tick { background: var(--primary); border-color: var(--primary); color: var(--on-primary); }
  .importing .bar { height: 10px; border-radius: 5px; background: var(--surface-3); overflow: hidden; }
  .importing .bar span { display: block; height: 100%; background: var(--primary); border-radius: 5px; transition: width 0.4s var(--ease); }
  .bubbles { display: grid; grid-template-columns: repeat(auto-fill, minmax(104px, 1fr)); gap: 18px 12px; margin-top: 20px; }
  .bubble { display: flex; flex-direction: column; align-items: center; gap: 8px; text-align: center; }
  .ph { position: relative; width: 100%; transition: transform 0.3s var(--ease-spring); }
  .bubble.on .ph { transform: scale(0.92); }
  .bubble.on .ph :global(.cover) { box-shadow: 0 0 0 4px var(--bg), 0 0 0 7px var(--primary); }
  .ok { position: absolute; right: 0; bottom: 0; width: 34px; height: 34px; border-radius: 50%; display: grid; place-items: center; background: var(--primary); color: var(--on-primary); box-shadow: 0 0 0 3px var(--bg); }
  .an { font-weight: 620; font-size: 0.92rem; }
  @media (max-width: 560px) { .themes { grid-template-columns: 1fr 1fr 1fr; gap: 8px; } .tl { font-size: 0.85rem; } }
</style>
