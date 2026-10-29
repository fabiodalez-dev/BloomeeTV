<script>
  // Accesso, registrazione con invito e primo avvio (account amministratore).
  import { post } from "../lib/api.js";
  import { session, loadSession } from "../lib/state.svelte.js";
  let mode = $state(session.setup ? "setup" : new URLSearchParams(location.search).get("invito") ? "register" : "login");
  let username = $state("");
  let password = $state("");
  let displayName = $state("");
  let invite = $state(new URLSearchParams(location.search).get("invito") || "");
  let error = $state("");
  let busy = $state(false);
  const copy = {
    login: { title: "Bentornato", lead: "Accedi per riprendere da dove avevi lasciato.", cta: "Accedi" },
    register: { title: "Benvenuto", lead: "Hai un codice d'invito: scegli nome utente e password.", cta: "Crea account" },
    setup: { title: "Primo avvio", lead: "Crea l'account amministratore. Poi potrai invitare altre persone.", cta: "Crea amministratore" }
  };
  async function submit(e) {
    e.preventDefault();
    error = "";
    busy = true;
    try {
      if (mode === "login") await post("/api/login", { username, password }, { quiet401: true });
      else if (mode === "register") await post("/api/register", { invite, username, password, displayName });
      else await post("/api/setup", { username, password, displayName });
      history.replaceState({}, "", "/");
      await loadSession();
    } catch (err) {
      error = err.message;
    } finally {
      busy = false;
    }
  }
</script>

<div class="wrap">
  <div class="art" aria-hidden="true">
    <span class="c c1"></span><span class="c c2"></span><span class="c c3"></span>
    <p class="display word">Fabio<br />Music</p>
  </div>
  <form class="card" onsubmit={submit}>
    <h1 class="headline">{copy[mode].title}</h1>
    <p class="muted lead">{copy[mode].lead}</p>
    {#if mode === "register"}
      <label for="invite" class="label">Codice d'invito</label>
      <input id="invite" class="field code" bind:value={invite} autocomplete="off" placeholder="ABCDE-FGHJK" required />
    {/if}
    {#if mode !== "login"}
      <label for="dname" class="label">Come ti chiami</label>
      <input id="dname" class="field" bind:value={displayName} autocomplete="name" maxlength="64" />
    {/if}
    <label for="user" class="label">Nome utente</label>
    <input id="user" class="field" bind:value={username} autocomplete="username" autocapitalize="none" spellcheck="false" required />
    <label for="pw" class="label">Password</label>
    <input id="pw" class="field" type="password" bind:value={password} autocomplete={mode === "login" ? "current-password" : "new-password"} minlength={mode === "login" ? undefined : 8} required />
    {#if mode !== "login"}<p class="hint muted">Almeno 8 caratteri.</p>{/if}
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    <button class="btn filled big" disabled={busy}>{busy ? "Un momento…" : copy[mode].cta}</button>
    {#if mode === "login"}
      <button type="button" class="btn text" onclick={() => ((mode = "register"), (error = ""))}>Ho un codice d'invito</button>
    {:else if mode === "register"}
      <button type="button" class="btn text" onclick={() => ((mode = "login"), (error = ""))}>Ho già un account</button>
    {/if}
  </form>
</div>

<style>
  .wrap { min-height: 100vh; display: grid; grid-template-columns: 1.1fr 1fr; }
  .art { position: relative; overflow: hidden; background: var(--primary-container); color: var(--on-primary-container); display: flex; align-items: end; padding: clamp(24px, 5vw, 64px); }
  .word { position: relative; font-size: clamp(3.5rem, 2rem + 6vw, 8.5rem); }
  .c { position: absolute; clip-path: url(#cookie); background: var(--primary); opacity: 0.9; animation: turn 60s linear infinite; }
  .c1 { width: 46vmin; height: 46vmin; right: -8vmin; top: -6vmin; }
  .c2 { width: 22vmin; height: 22vmin; left: 12%; top: 18%; background: var(--tertiary); animation-duration: 40s; animation-direction: reverse; }
  .c3 { width: 12vmin; height: 12vmin; right: 34%; top: 46%; background: var(--on-primary-container); opacity: 0.18; }
  @keyframes turn { to { transform: rotate(360deg); } }
  .card { align-self: center; justify-self: center; width: min(420px, 100%); padding: 32px 24px; display: flex; flex-direction: column; gap: 8px; }
  .lead { margin: 0 0 18px; }
  .label { margin-top: 8px; }
  .code { text-transform: uppercase; letter-spacing: 0.12em; font-variant-numeric: tabular-nums; }
  .hint { margin: 2px 0 0; font-size: 0.85rem; }
  .error { color: var(--error); margin: 8px 0 0; font-weight: 560; }
  .btn.big { margin-top: 18px; }
  @media (max-width: 800px) {
    .wrap { grid-template-columns: 1fr; grid-template-rows: 34vh auto; }
    .word { font-size: clamp(3rem, 14vw, 5rem); }
  }
</style>
