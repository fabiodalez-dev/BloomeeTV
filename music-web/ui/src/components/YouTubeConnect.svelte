<script>
  // Collega l'account YouTube Music: con un codice da approvare su
  // google.com/device (come sulle TV) oppure incollando il cookie.
  import { onDestroy } from "svelte";
  import Icon from "./Icon.svelte";
  import * as I from "../lib/icons.js";
  import { post, put, del } from "../lib/api.js";
  import { session, toast } from "../lib/state.svelte.js";
  let { onconnected } = $props();
  let method = $state(session.youtubeCode ? "code" : "cookie");
  let code = $state(null); // { userCode, url, interval, expires }
  let status = $state("");
  let error = $state("");
  let busy = $state(false);
  let cookie = $state("");
  let dataSyncId = $state("");
  let timer;
  onDestroy(() => clearTimeout(timer));

  async function startCode() {
    error = "";
    busy = true;
    try {
      code = await post("/api/youtube-account/code");
      status = "In attesa che approvi il codice";
      schedule(code.interval);
    } catch (e) {
      error = e.message;
    } finally {
      busy = false;
    }
  }
  function schedule(secs) {
    clearTimeout(timer);
    timer = setTimeout(check, Math.max(3, secs) * 1000);
  }
  async function check() {
    try {
      const d = await post("/api/youtube-account/code/check");
      if (d.status === "ok") return done(d.account);
      if (d.status === "pending") return schedule(code.interval);
      if (d.status === "slow") return schedule(code.interval + 5);
      code = null;
      error = d.message;
    } catch (e) {
      code = null;
      error = e.message;
    }
  }
  async function link(e) {
    e.preventDefault();
    error = "";
    busy = true;
    try {
      const d = await put("/api/youtube-account", { cookie, dataSyncId });
      cookie = dataSyncId = "";
      done(d.account);
    } catch (err) {
      error = err.message;
    } finally {
      busy = false;
    }
  }
  function done(account) {
    clearTimeout(timer);
    code = null;
    session.youtube = account;
    toast("Collegato come " + account.name);
    onconnected?.(account);
  }
  async function unlink() {
    await del("/api/youtube-account");
    session.youtube = null;
    toast("Account YouTube Music scollegato");
  }
  function copy(text) {
    navigator.clipboard.writeText(text).then(() => toast("Codice copiato"), () => {});
  }
</script>

{#if session.youtube}
  <div class="linked">
    <span class="yt"><Icon path={I.mdiYoutube} size={28} /></span>
    <span class="txt"><span class="l">Collegato come {session.youtube.name}</span><span class="muted h">{session.youtube.method === "code" ? "Con il codice di Google" : "Con il cookie del browser"}</span></span>
    <button class="btn outline" onclick={unlink}>Scollega</button>
  </div>
{:else}
  <div class="methods" role="tablist">
    {#if session.youtubeCode}<button role="tab" aria-selected={method === "code"} class="chip" class:on={method === "code"} onclick={() => (method = "code")}>Con un codice</button>{/if}
    <button role="tab" aria-selected={method === "cookie"} class="chip" class:on={method === "cookie"} onclick={() => (method = "cookie")}>Con il cookie</button>
  </div>

  {#if method === "code"}
    {#if code}
      <div class="code-box">
        <p class="muted">Apri questa pagina sul telefono o sul computer, accedi a Google con l'account di YouTube Music e scrivi il codice:</p>
        <a class="btn tonal" href={code.url} target="_blank" rel="noopener noreferrer"><Icon path={I.mdiLinkVariant} size={20} /> {code.url.replace(/^https:\/\//, "")}</a>
        <button class="code" onclick={() => copy(code.userCode)} aria-label="Codice {code.userCode}, tocca per copiarlo">{code.userCode}</button>
        <p class="wait"><span class="dot"></span> {status}</p>
        <button class="btn text" onclick={() => ((code = null), clearTimeout(timer))}>Annulla</button>
      </div>
    {:else}
      <p class="muted h">Come sulle smart TV: ti do un codice, lo approvi su google.com/device da qualsiasi dispositivo. La password resta a Google.</p>
      <button class="btn filled" disabled={busy} onclick={startCode}><Icon path={I.mdiYoutube} size={20} /> {busy ? "Un momento…" : "Ricevi il codice"}</button>
    {/if}
  {:else}
    <form class="cookie" onsubmit={link}>
      <ol class="muted h steps">
        <li>Da un computer apri <a href="https://music.youtube.com" target="_blank" rel="noopener noreferrer">music.youtube.com</a> con l'accesso fatto.</li>
        <li>Apri gli strumenti per sviluppatori (F12, oppure Cmd+Opzione+I su Mac) e vai alla scheda Rete.</li>
        <li>Ricarica la pagina, scrivi <code>browse</code> nel filtro e scegli una richiesta.</li>
        <li>In Intestazioni richiesta copia tutto il valore di <code>cookie</code> e incollalo qui.</li>
      </ol>
      <textarea class="field" bind:value={cookie} rows="3" placeholder="Incolla qui il cookie" aria-label="Cookie di music.youtube.com" spellcheck="false" autocomplete="off"></textarea>
      <input class="field" bind:value={dataSyncId} placeholder="DATASYNC_ID, solo per gli account brand" aria-label="DATASYNC_ID per account brand" spellcheck="false" />
      <p class="muted h">Il cookie dà accesso al tuo account Google: viene cifrato sul server e usato solo per le tue richieste. Scade se esci da Google su quel browser.</p>
      <button class="btn filled" disabled={busy || !cookie.trim()}>{busy ? "Verifico…" : "Collega"}</button>
    </form>
  {/if}
  {#if error}<p class="error" role="alert">{error}</p>{/if}
{/if}

<style>
  .linked { display: flex; align-items: center; gap: 14px; }
  .yt { color: #f33; }
  .txt { flex: 1; display: flex; flex-direction: column; min-width: 0; }
  .l { font-weight: 600; }
  .h { font-size: 0.9rem; }
  .methods { display: flex; gap: 8px; margin-bottom: 14px; }
  .code-box { display: flex; flex-direction: column; align-items: start; gap: 12px; }
  .code-box p { margin: 0; }
  .code {
    font-size: clamp(2rem, 1.4rem + 3vw, 3.2rem); font-weight: 860; font-stretch: 125%; letter-spacing: 0.08em; font-variant-numeric: tabular-nums;
    padding: 10px 22px; border-radius: var(--radius-m); background: var(--primary-container); color: var(--on-primary-container);
  }
  .wait { display: flex; align-items: center; gap: 10px; color: var(--muted); }
  .dot { width: 10px; height: 10px; border-radius: 50%; background: var(--primary); animation: pulse 1.2s ease-in-out infinite; }
  @keyframes pulse { 50% { opacity: 0.3; transform: scale(0.7); } }
  .cookie { display: flex; flex-direction: column; gap: 10px; }
  .cookie .btn { align-self: start; }
  .steps { margin: 0; padding-left: 20px; display: flex; flex-direction: column; gap: 4px; }
  .steps a { color: var(--primary); text-decoration: underline; }
  code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.9em; }
  .error { color: var(--error); font-weight: 560; margin: 10px 0 0; }
</style>
