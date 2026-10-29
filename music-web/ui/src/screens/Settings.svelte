<script>
  // Impostazioni: profilo, aspetto, riproduzione ed equalizzatore, account
  // YouTube Music e, per gli amministratori, inviti e utenti.
  import { onMount } from "svelte";
  import Toggle from "../components/Toggle.svelte";
  import YouTubeConnect from "../components/YouTubeConnect.svelte";
  import Icon from "../components/Icon.svelte";
  import * as I from "../lib/icons.js";
  import { get, post, put, patch, del } from "../lib/api.js";
  import { session, settings, saveSettings, toast, logout } from "../lib/state.svelte.js";
  import { player, EQ_FREQS, EQ_PRESETS } from "../lib/player.svelte.js";
  import { ago } from "../lib/format.js";

  // Profilo
  let displayName = $state(session.user.displayName);
  let oldPw = $state("");
  let newPw = $state("");
  async function saveName(e) {
    e.preventDefault();
    try {
      await patch("/api/profile", { displayName });
      session.user.displayName = displayName.trim();
      toast("Nome aggiornato");
    } catch (err) {
      toast(err.message);
    }
  }
  async function changePw(e) {
    e.preventDefault();
    try {
      await post("/api/password", { old: oldPw, new: newPw });
      oldPw = newPw = "";
      toast("Password cambiata. Gli altri dispositivi devono accedere di nuovo.");
    } catch (err) {
      toast(err.message);
    }
  }

  // Impostazioni salvate sul server
  function set(k, v) {
    settings[k] = v;
    saveSettings();
  }
  function eqChange() {
    player.applyEq();
    saveSettings();
  }
  function preset(k) {
    settings.eq.preset = k;
    settings.eq.gains = EQ_PRESETS[k][1].slice();
    if (!settings.eq.enabled) settings.eq.enabled = true;
    eqChange();
  }
  function band(i, v) {
    settings.eq.gains[i] = v;
    settings.eq.preset = "custom";
    eqChange();
  }

  function rerunWizard() {
    settings.onboarded = false;
    saveSettings();
  }

  // Accesso con codice di Google (configurato dall'amministratore)
  let google = $state(null);
  let clientId = $state("");
  let clientSecret = $state("");
  async function loadGoogle() {
    if (session.user.admin) google = await get("/api/admin/google-oauth");
  }
  async function saveGoogle(e) {
    e.preventDefault();
    try {
      await put("/api/admin/google-oauth", { clientId, clientSecret });
      clientId = clientSecret = "";
      session.youtubeCode = true;
      await loadGoogle();
      toast("Accesso con codice attivato");
    } catch (err) {
      toast(err.message);
    }
  }
  async function removeGoogle() {
    if (!confirm("Disattivare l'accesso con codice? Gli account già collegati con il codice smetteranno di funzionare.")) return;
    await del("/api/admin/google-oauth");
    session.youtubeCode = false;
    loadGoogle();
  }

  // Amministrazione
  let invites = $state([]);
  let users = $state([]);
  let days = $state(7);
  let note = $state("");
  let fresh = $state(null);
  async function loadAdmin() {
    if (!session.user.admin) return;
    const [a, b] = await Promise.all([get("/api/admin/invites"), get("/api/admin/users")]);
    invites = a.invites;
    users = b.users;
  }
  onMount(() => {
    loadAdmin().catch((e) => toast(e.message));
    loadGoogle().catch(() => {});
  });
  async function invite(e) {
    e.preventDefault();
    try {
      const d = await post("/api/admin/invites", { days, note });
      fresh = d.code;
      note = "";
      loadAdmin();
    } catch (err) {
      toast(err.message);
    }
  }
  function inviteLink(code) {
    return location.origin + "/?invito=" + code;
  }
  function copy(text) {
    navigator.clipboard.writeText(text).then(() => toast("Copiato"), () => toast("Impossibile copiare"));
  }
  async function revoke(code) {
    await del("/api/admin/invites/" + code);
    loadAdmin();
  }
  async function setUser(u, data) {
    try {
      await patch("/api/admin/users/" + u.id, data);
      loadAdmin();
    } catch (err) {
      toast(err.message);
    }
  }
</script>

<div class="page narrow">
  <h1 class="display">Impostazioni</h1>

  <section>
    <h2 class="title">Aspetto</h2>
    <div class="group">
      <div class="seg-row">
        <span class="l">Tema</span>
        <div class="seg" role="radiogroup" aria-label="Tema">
          {#each [["auto", "Automatico", I.mdiThemeLightDark], ["light", "Chiaro", I.mdiWhiteBalanceSunny], ["dark", "Scuro", I.mdiWeatherNight]] as [k, label, icon]}
            <button role="radio" aria-checked={settings.theme === k} class:on={settings.theme === k} onclick={() => set("theme", k)}><Icon path={icon} size={18} /> {label}</button>
          {/each}
        </div>
      </div>
      <Toggle bind:checked={settings.dynamicColor} label="Colori dalla copertina" hint="L'interfaccia prende i colori dell'album in ascolto" onchange={saveSettings} />
      <Toggle bind:checked={settings.rotateCover} label="Copertina che gira" hint="Nel lettore a schermo intero, mentre la musica suona" onchange={saveSettings} />
    </div>
  </section>

  <section>
    <h2 class="title">Riproduzione</h2>
    <div class="group">
      <Toggle bind:checked={settings.autoplay} label="Riproduzione automatica" hint="Alla fine della coda continua con la radio dell'ultimo brano" onchange={saveSettings} />
      <div class="slider-row">
        <span class="txt"><span class="l">Crossfade</span><span class="muted h">{settings.crossfade ? settings.crossfade + " secondi tra un brano e l'altro" : "Spento: i brani si susseguono senza sfumare"}</span></span>
        <input type="range" min="0" max="12" step="1" value={settings.crossfade} oninput={(e) => set("crossfade", +e.currentTarget.value)} aria-label="Durata del crossfade in secondi" />
      </div>
      <div class="seg-row">
        <span class="txt"><span class="l">Formato audio</span><span class="muted h">Compatibile usa AAC: utile sui browser che non leggono Opus</span></span>
        <div class="seg" role="radiogroup" aria-label="Formato audio">
          {#each [["auto", "Automatico"], ["aac", "Compatibile"]] as [k, label]}
            <button role="radio" aria-checked={settings.quality === k} class:on={settings.quality === k} onclick={() => set("quality", k)}>{label}</button>
          {/each}
        </div>
      </div>
    </div>
  </section>

  <section>
    <h2 class="title">Equalizzatore</h2>
    <div class="group">
      <Toggle bind:checked={settings.eq.enabled} label="Attiva l'equalizzatore" hint="Su iPhone e iPad può fermare l'audio quando lo schermo è spento" onchange={eqChange} />
      <div class="eq" class:off={!settings.eq.enabled}>
        <div class="presets">
          {#each Object.entries(EQ_PRESETS) as [k, [label]]}<button class="chip" class:on={settings.eq.preset === k} onclick={() => preset(k)}>{label}</button>{/each}
          {#if settings.eq.preset === "custom"}<span class="chip on">Personalizzato</span>{/if}
        </div>
        <div class="bands">
          {#each EQ_FREQS as f, i}
            <label class="band">
              <span class="db">{settings.eq.gains[i] > 0 ? "+" : ""}{settings.eq.gains[i]}</span>
              <input type="range" min="-12" max="12" step="1" value={settings.eq.gains[i]} oninput={(e) => band(i, +e.currentTarget.value)} aria-label="{f >= 1000 ? f / 1000 + ' kHz' : f + ' Hz'}, decibel" />
              <span class="hz">{f >= 1000 ? f / 1000 + "k" : f}</span>
            </label>
          {/each}
        </div>
        <div class="slider-row pre">
          <span class="txt"><span class="l">Preamplificazione</span><span class="muted h">{settings.eq.preamp} dB. Abbassala se con i bassi alzati il suono distorce</span></span>
          <input type="range" min="-12" max="6" step="1" value={settings.eq.preamp} oninput={(e) => ((settings.eq.preamp = +e.currentTarget.value), eqChange())} aria-label="Preamplificazione in decibel" />
        </div>
      </div>
    </div>
  </section>

  <section>
    <h2 class="title">YouTube Music</h2>
    <div class="group"><div class="pad"><YouTubeConnect /></div></div>
  </section>

  <section>
    <h2 class="title">Profilo</h2>
    <div class="group">
      <form class="pad inline" onsubmit={saveName}>
        <label class="l" for="dn">Nome visualizzato</label>
        <input id="dn" class="field" bind:value={displayName} maxlength="64" />
        <button class="btn tonal" disabled={!displayName.trim() || displayName === session.user.displayName}>Salva</button>
      </form>
      <form class="pad inline" onsubmit={changePw}>
        <span class="l">Cambia password</span>
        <input class="field" type="password" bind:value={oldPw} placeholder="Password attuale" autocomplete="current-password" aria-label="Password attuale" />
        <input class="field" type="password" bind:value={newPw} placeholder="Nuova password, almeno 8 caratteri" autocomplete="new-password" minlength="8" aria-label="Nuova password" />
        <button class="btn tonal" disabled={!oldPw || newPw.length < 8}>Cambia password</button>
      </form>
      <div class="pad yt">
        <span class="txt"><span class="l">Configurazione iniziale</span><span class="muted h">Rifai il percorso di benvenuto: aspetto, account, importazione, artisti</span></span>
        <button class="btn outline" onclick={rerunWizard}>Riapri</button>
      </div>
      <div class="pad yt">
        <span class="txt"><span class="l">{session.user.displayName}</span><span class="muted h">Accesso come {session.user.username}{session.user.admin ? ", amministratore" : ""}</span></span>
        <button class="btn outline" onclick={logout}><Icon path={I.mdiLogout} size={20} /> Esci</button>
      </div>
    </div>
  </section>

  {#if session.user.admin}
    <section>
      <h2 class="title">Inviti</h2>
      <div class="group">
        <form class="pad inline" onsubmit={invite}>
          <span class="l">Invita una persona</span>
          <div class="two">
            <input class="field" bind:value={note} placeholder="Per chi è (facoltativo)" maxlength="120" aria-label="Nota sull'invito" />
            <select class="field" bind:value={days} aria-label="Validità"><option value={1}>Vale 1 giorno</option><option value={7}>Vale 7 giorni</option><option value={30}>Vale 30 giorni</option></select>
          </div>
          <button class="btn filled"><Icon path={I.mdiTicketConfirmation} size={20} /> Crea invito</button>
          {#if fresh}
            <div class="fresh">
              <code class="code">{fresh}</code>
              <button type="button" class="btn tonal" onclick={() => copy(inviteLink(fresh))}><Icon path={I.mdiLinkVariant} size={18} /> Copia link</button>
              <button type="button" class="btn text" onclick={() => copy(fresh)}>Copia codice</button>
            </div>
          {/if}
        </form>
        {#each invites as inv}
          <div class="pad yt small">
            <code class="code sm">{inv.code}</code>
            <span class="txt"><span>{inv.note || "Invito"}</span><span class="muted h">{inv.usedBy ? "Usato da " + inv.usedBy + ", " + ago(inv.usedAt) : inv.expires < Date.now() / 1000 ? "Scaduto" : "Valido fino al " + new Date(inv.expires * 1000).toLocaleDateString("it-IT")}</span></span>
            {#if !inv.usedBy}<button class="icon-btn" onclick={() => revoke(inv.code)} aria-label="Revoca invito {inv.code}"><Icon path={I.mdiDelete} size={20} /></button>{/if}
          </div>
        {/each}
      </div>
    </section>

    <section>
      <h2 class="title">Accesso a YouTube con codice</h2>
      <div class="group">
        {#if google && google.configured}
          <div class="pad yt">
            <Icon path={I.mdiCheck} size={24} />
            <span class="txt"><span class="l">Attivo</span><span class="muted h ellipsis">Client {google.clientId}</span></span>
            <button class="btn outline" onclick={removeGoogle}>Disattiva</button>
          </div>
        {:else}
          <form class="pad inline" onsubmit={saveGoogle}>
            <p class="muted h">Permette a tutti gli utenti di collegare YouTube Music con un codice da approvare su google.com/device, come sulle TV. Va fatto una volta sola:</p>
            <ol class="muted h steps">
              <li>Apri <a href="https://console.cloud.google.com/projectcreate" target="_blank" rel="noopener noreferrer">Google Cloud Console</a> e crea un progetto (per esempio «Fabio Music»).</li>
              <li>In <a href="https://console.cloud.google.com/apis/library/youtube.googleapis.com" target="_blank" rel="noopener noreferrer">Libreria API</a> attiva «YouTube Data API v3».</li>
              <li>In <a href="https://console.cloud.google.com/auth/branding" target="_blank" rel="noopener noreferrer">Schermata consenso OAuth</a> scegli «Esterno», metti nome e email; in «Destinatari» aggiungi come utenti di test gli account Google di chi userà il sito.</li>
              <li>In <a href="https://console.cloud.google.com/auth/clients" target="_blank" rel="noopener noreferrer">Client</a> crea un client OAuth di tipo «TV e dispositivi con input limitato».</li>
              <li>Copia qui ID client e secret.</li>
            </ol>
            <input class="field" bind:value={clientId} placeholder="ID client (…apps.googleusercontent.com)" aria-label="ID client OAuth" spellcheck="false" autocomplete="off" />
            <input class="field" type="password" bind:value={clientSecret} placeholder="Secret del client" aria-label="Secret del client OAuth" autocomplete="off" />
            <button class="btn filled" disabled={!clientId.trim() || !clientSecret.trim()}>Attiva</button>
          </form>
        {/if}
      </div>
    </section>

    <section>
      <h2 class="title">Utenti</h2>
      <div class="group">
        {#each users as u (u.id)}
          <div class="pad yt small">
            <Icon path={I.mdiAccountCircle} size={28} />
            <span class="txt"><span class="l">{u.displayName} <span class="muted">({u.username})</span></span><span class="muted h">{u.admin ? "Amministratore. " : ""}{u.disabled ? "Disattivato. " : ""}{u.plays} ascolti{u.lastPlay ? ", ultimo " + ago(u.lastPlay) : ""}</span></span>
            {#if u.id !== session.user.id}
              <button class="btn text" onclick={() => setUser(u, { disabled: !u.disabled })}>{u.disabled ? "Riattiva" : "Disattiva"}</button>
            {/if}
          </div>
        {/each}
      </div>
    </section>
  {/if}
</div>

<style>
  .narrow { max-width: 820px; }
  section { margin-top: 32px; }
  section > .title { margin: 0 0 12px 4px; }
  .group > * { background: var(--surface); }
  .pad { padding: 16px; }
  .l { font-weight: 600; }
  .h { font-size: 0.87rem; }
  .txt { flex: 1; display: flex; flex-direction: column; min-width: 0; }
  .seg-row, .slider-row { display: flex; align-items: center; gap: 16px; padding: 14px 16px; flex-wrap: wrap; }
  .seg-row .l { flex: 1; }
  .seg { display: inline-flex; border: 1px solid var(--outline); border-radius: 999px; overflow: hidden; }
  .seg button { display: inline-flex; align-items: center; gap: 6px; height: 40px; padding: 0 14px; font-weight: 560; border-right: 1px solid var(--outline); }
  .seg button:last-child { border-right: 0; }
  .seg button.on { background: var(--primary-container); color: var(--on-primary-container); }
  input[type="range"] { accent-color: var(--primary); }
  .slider-row input { width: min(260px, 100%); }
  .eq { padding: 4px 16px 16px; transition: opacity 0.2s; }
  .eq.off { opacity: 0.5; }
  .presets { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 18px; }
  .bands { display: grid; grid-template-columns: repeat(10, 1fr); gap: 4px; }
  .band { display: flex; flex-direction: column; align-items: center; gap: 6px; }
  .band input { writing-mode: vertical-lr; direction: rtl; height: 150px; width: 28px; }
  .db { font-size: 0.75rem; font-variant-numeric: tabular-nums; color: var(--muted); }
  .hz { font-size: 0.75rem; color: var(--muted); }
  .pre { padding: 14px 0 0; }
  .yt { display: flex; align-items: center; gap: 14px; }
  .inline { display: flex; flex-direction: column; gap: 10px; align-items: stretch; }
  .inline .btn { align-self: start; }
  .steps { margin: 0; padding-left: 20px; display: flex; flex-direction: column; gap: 4px; }
  .steps a { color: var(--primary); text-decoration: underline; }
  code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.9em; }
  .two { display: grid; grid-template-columns: 1fr 180px; gap: 8px; }
  .fresh { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; padding: 12px; border-radius: var(--radius-s); background: var(--primary-container); color: var(--on-primary-container); }
  .code { font-size: 1.3rem; letter-spacing: 0.08em; font-weight: 700; margin-right: auto; }
  .code.sm { font-size: 0.95rem; margin-right: 0; }
  .small { padding: 10px 16px; }
  @media (max-width: 560px) { .two { grid-template-columns: 1fr; } .bands input { height: 120px; } }
</style>
