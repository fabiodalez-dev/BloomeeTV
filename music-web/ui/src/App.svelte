<script>
  import { onMount } from "svelte";
  import Icon from "./components/Icon.svelte";
  import PlayerBar from "./components/PlayerBar.svelte";
  import NowPlaying from "./components/NowPlaying.svelte";
  import ItemMenu from "./components/ItemMenu.svelte";
  import AddToPlaylist from "./components/AddToPlaylist.svelte";
  import Toasts from "./components/Toasts.svelte";
  import Lyrics from "./components/Lyrics.svelte";
  import Queue from "./components/Queue.svelte";
  import Login from "./screens/Login.svelte";
  import Home from "./screens/Home.svelte";
  import Explore from "./screens/Explore.svelte";
  import Search from "./screens/Search.svelte";
  import Artist from "./screens/Artist.svelte";
  import Collection from "./screens/Collection.svelte";
  import Browse from "./screens/Browse.svelte";
  import Library from "./screens/Library.svelte";
  import MyPlaylist from "./screens/MyPlaylist.svelte";
  import Recap from "./screens/Recap.svelte";
  import Settings from "./screens/Settings.svelte";
  import Onboarding from "./screens/Onboarding.svelte";
  import * as I from "./lib/icons.js";
  import { session, settings, library, route, navigate, ui, loadSession } from "./lib/state.svelte.js";
  import { player } from "./lib/player.svelte.js";
  import { seedFromImage, applySeed } from "./lib/color.js";
  import { cookiePath } from "./lib/format.js";

  const cookie = cookiePath(9, 0.045);
  const nav = [
    { href: "/", label: "Home", icon: I.mdiHomeOutline, on: I.mdiHome },
    { href: "/explore", label: "Esplora", icon: I.mdiCompassOutline, on: I.mdiCompass },
    { href: "/search", label: "Cerca", icon: I.mdiMagnify, on: I.mdiMagnify },
    { href: "/library", label: "Libreria", icon: I.mdiBookshelf, on: I.mdiBookshelf }
  ];

  onMount(() => {
    loadSession();
  });

  // Tema: automatico segue il sistema.
  let systemDark = $state(matchMedia("(prefers-color-scheme: dark)").matches);
  onMount(() => {
    const mq = matchMedia("(prefers-color-scheme: dark)");
    const f = (e) => (systemDark = e.matches);
    mq.addEventListener("change", f);
    return () => mq.removeEventListener("change", f);
  });
  let dark = $derived(settings.theme === "dark" || (settings.theme === "auto" && systemDark));
  $effect(() => {
    document.documentElement.dataset.theme = dark ? "dark" : "light";
  });

  // Colore dinamico dalla copertina in ascolto.
  $effect(() => {
    const url = player.current && player.current.thumbnail;
    if (!settings.dynamicColor || !url) {
      applySeed(null);
      return;
    }
    let live = true;
    seedFromImage(url).then((s) => live && applySeed(s));
    return () => (live = false);
  });
  $effect(() => {
    void settings.dynamicColor, void dark, void player.current;
    requestAnimationFrame(() => {
      const bg = getComputedStyle(document.body).backgroundColor;
      document.querySelector('meta[name="theme-color"]')?.setAttribute("content", bg);
    });
  });

  $effect(() => {
    if (session.user) player.init();
  });
  $effect(() => {
    if (session.user && settings.eq) player.applyEq();
  });

  function active(href) {
    return href === "/" ? route.path === "/" : route.path.startsWith(href);
  }
  function go(e, href) {
    e.preventDefault();
    navigate(href);
  }

  let screen = $derived.by(() => {
    const p = route.path;
    let m;
    if (p === "/") return { c: Home };
    if (p === "/explore") return { c: Explore };
    if (p === "/search") return { c: Search };
    if (p.startsWith("/library")) return { c: Library, props: { tab: p.split("/")[2] || "playlists" } };
    if ((m = p.match(/^\/artist\/([\w-]+)$/))) return { c: Artist, props: { id: m[1] } };
    if ((m = p.match(/^\/(album|playlist)\/([\w-]+)$/))) return { c: Collection, props: { id: m[2] } };
    if ((m = p.match(/^\/browse\/([\w-]+)$/))) return { c: Browse, props: { id: m[1], params: route.query.params || null } };
    if ((m = p.match(/^\/my\/(\d+)$/))) return { c: MyPlaylist, props: { id: +m[1] } };
    if (p === "/recap") return { c: Recap };
    if (p.startsWith("/settings")) return { c: Settings, props: { tab: p.split("/")[2] || "" } };
    return { c: Home };
  });

  // Scorciatoie da tastiera: spazio, frecce, / per cercare.
  function keys(e) {
    if (!session.user || ui.nowPlaying || ui.menu || e.target.closest("input, textarea, select, [contenteditable], [role=slider]")) return;
    if (e.key === " " && !e.target.closest("button, a")) {
      e.preventDefault();
      player.toggle();
    } else if (e.key === "/") {
      e.preventDefault();
      navigate("/search");
    } else if (e.altKey && e.key === "ArrowRight") player.next();
    else if (e.altKey && e.key === "ArrowLeft") player.prev();
  }
</script>

<svelte:window onkeydown={keys} />

<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  <clipPath id="cookie" clipPathUnits="objectBoundingBox"><path d={cookie} /></clipPath>
</svg>

{#if session.loading}
  <div class="boot" aria-label="Caricamento"><span class="blob"></span></div>
{:else if !session.user}
  <Login />
{:else}
  <div class="shell" class:has-player={!!player.current} class:has-side={!!ui.side && !!player.current}>
    <nav class="rail" aria-label="Sezioni">
      <a class="brand" href="/" onclick={(e) => go(e, "/")} aria-label="Fabio Music, Home">
        <span class="mark" aria-hidden="true"></span>
      </a>
      {#each nav as n}
        <a href={n.href} class="dest" class:on={active(n.href)} aria-current={active(n.href) ? "page" : undefined} onclick={(e) => go(e, n.href)}>
          <span class="pill"><Icon path={active(n.href) ? n.on : n.icon} /></span>
          <span class="lbl">{n.label}</span>
        </a>
      {/each}
      <span class="grow"></span>
      <a href="/recap" class="dest" class:on={active("/recap")} onclick={(e) => go(e, "/recap")}>
        <span class="pill"><Icon path={I.mdiChartBox} /></span><span class="lbl">Recap</span>
      </a>
      <a href="/settings" class="dest" class:on={active("/settings")} onclick={(e) => go(e, "/settings")}>
        <span class="pill"><Icon path={I.mdiCog} /></span><span class="lbl">Impostazioni</span>
      </a>
    </nav>

    <main id="main">
      {#key route.path + (route.query.params || "")}
        <screen.c {...screen.props || {}} />
      {/key}
    </main>

    {#if ui.side && player.current}
      <aside class="side" aria-label={ui.side === "lyrics" ? "Testo" : "Coda"}>
        <div class="side-head">
          <h2 class="title">{ui.side === "lyrics" ? "Testo" : "Coda"}</h2>
          <button class="icon-btn" onclick={() => (ui.side = null)} aria-label="Chiudi il pannello"><Icon path={I.mdiClose} /></button>
        </div>
        <div class="side-body">{#if ui.side === "lyrics"}<Lyrics />{:else}<Queue />{/if}</div>
      </aside>
    {/if}

    <PlayerBar />
  </div>

  {#if library.loaded && !settings.onboarded}<Onboarding />{/if}
  {#if ui.nowPlaying}<NowPlaying />{/if}
  {#if ui.menu}<ItemMenu />{/if}
  {#if ui.addTo}<AddToPlaylist />{/if}
{/if}
<Toasts />

<style>
  .boot { position: fixed; inset: 0; display: grid; place-items: center; }
  .blob { width: 64px; height: 64px; background: var(--primary); clip-path: url(#cookie); animation: spin 2.4s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }

  .shell { display: grid; grid-template-columns: var(--rail) minmax(0, 1fr); min-height: 100vh; }
  .shell.has-side { grid-template-columns: var(--rail) minmax(0, 1fr) 380px; }
  main { min-width: 0; padding-bottom: 24px; }
  .has-player main { padding-bottom: calc(var(--bar) + 24px); }

  .rail {
    position: sticky; top: 0; height: 100vh; display: flex; flex-direction: column; align-items: center; gap: 4px;
    padding: 18px 0 calc(var(--bar) + 12px);
  }
  .shell:not(.has-player) .rail { padding-bottom: 18px; }
  .brand { margin-bottom: 18px; }
  .mark { display: block; width: 44px; height: 44px; background: var(--primary); clip-path: url(#cookie); transition: transform 0.6s var(--ease-spring); }
  .brand:hover .mark { transform: rotate(40deg) scale(1.05); }
  .dest { display: flex; flex-direction: column; align-items: center; gap: 4px; width: 80px; padding: 4px 0 8px; font-size: 0.75rem; font-weight: 600; color: var(--muted); }
  .pill { width: 56px; height: 32px; border-radius: 16px; display: grid; place-items: center; transition: background 0.25s, width 0.3s var(--ease-spring); }
  .dest:hover .pill { background: color-mix(in oklch, var(--on-bg) 8%, transparent); }
  .dest.on { color: var(--on-bg); }
  .dest.on .pill { background: var(--primary-container); color: var(--on-primary-container); }
  .grow { flex: 1; }

  .side {
    position: sticky; top: 0; height: calc(100vh - var(--bar)); display: flex; flex-direction: column;
    background: var(--surface); border-left: 1px solid color-mix(in oklch, var(--outline) 50%, transparent);
  }
  .side-head { display: flex; align-items: center; justify-content: space-between; padding: 14px 10px 4px 20px; }
  .side-body { flex: 1; min-height: 0; overflow: auto; padding: 0 10px; }

  @media (max-width: 1200px) {
    .shell.has-side { grid-template-columns: var(--rail) minmax(0, 1fr); }
    .side { position: fixed; right: 0; top: 0; bottom: var(--bar); width: min(380px, 100vw); z-index: 45; box-shadow: var(--shadow); }
  }
  @media (max-width: 860px) {
    .shell, .shell.has-side { grid-template-columns: 1fr; }
    .rail {
      position: fixed; z-index: 50; top: auto; bottom: 0; left: 0; right: 0; height: calc(76px + var(--safe-b)); flex-direction: row; justify-content: space-around;
      padding: 8px 4px calc(8px + var(--safe-b)); background: var(--surface); gap: 0;
    }
    .shell:not(.has-player) .rail { padding-bottom: calc(8px + var(--safe-b)); }
    .brand, .grow, .dest:nth-last-child(2) { display: none; }
    .dest { width: auto; flex: 1; }
    main { padding-bottom: calc(96px + var(--safe-b)); }
    .has-player main { padding-bottom: calc(170px + var(--safe-b)); }
    .side { display: none; }
  }
</style>
