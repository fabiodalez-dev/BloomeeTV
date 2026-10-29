// Chiamate al server. Le richieste che modificano dati portano l'header
// X-Requested-With: il server rifiuta quelle che non lo hanno (protezione CSRF).

export class ApiError extends Error {
  constructor(status, message, data) {
    super(message);
    this.status = status;
    this.data = data;
  }
}

let onUnauthorized = () => {};
export function setUnauthorizedHandler(f) {
  onUnauthorized = f;
}

export async function api(path, { method = "GET", body, signal, quiet401 = false, keepalive = false } = {}) {
  const headers = {};
  if (method !== "GET") headers["X-Requested-With"] = "fabio-music";
  if (body !== undefined) headers["Content-Type"] = "application/json";
  let res;
  try {
    res = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal, keepalive, credentials: "same-origin" });
  } catch (e) {
    if (e.name === "AbortError") throw e;
    throw new ApiError(0, "Nessuna connessione: controlla la rete e riprova");
  }
  let data = null;
  try {
    data = await res.json();
  } catch {
    data = null;
  }
  if (!res.ok) {
    if (res.status === 401 && !quiet401) onUnauthorized();
    throw new ApiError(res.status, (data && data.error) || "Errore del server (" + res.status + ")", data);
  }
  return data;
}

export const get = (path, opts) => api(path, opts);
export const post = (path, body, opts) => api(path, { ...opts, method: "POST", body: body || {} });
export const put = (path, body, opts) => api(path, { ...opts, method: "PUT", body: body || {} });
export const patch = (path, body, opts) => api(path, { ...opts, method: "PATCH", body: body || {} });
export const del = (path, opts) => api(path, { ...opts, method: "DELETE" });

// InnerTube attraverso il server. personal: true usa l'account YouTube collegato.
// Le pagine (browse) restano in memoria 10 minuti: tornare indietro è immediato.
const pages = new Map();
const PAGE_TTL = 10 * 60 * 1000;
export function yt(endpoint, body, opts) {
  if (endpoint !== "browse") return post("/api/yt/" + endpoint, body, opts);
  const key = JSON.stringify(body);
  const hit = pages.get(key);
  if (hit && Date.now() - hit.at < PAGE_TTL) return hit.promise;
  const promise = post("/api/yt/" + endpoint, body, opts);
  pages.set(key, { at: Date.now(), promise });
  promise.catch(() => pages.delete(key));
  if (pages.size > 60) pages.delete(pages.keys().next().value);
  return promise;
}

// Tutte le pagine di un elenco lungo (playlist, album, risultati), fino a maxPages.
export async function ytAll(endpoint, body, parse, nextOf, maxPages = 20, opts) {
  const first = await yt(endpoint, body, opts);
  let items = parse(first);
  let next = nextOf(first);
  for (let i = 1; next && i < maxPages; i++) {
    const page = await yt(endpoint, { continuation: next.token, legacy: next.legacy, personal: body.personal }, opts);
    const more = parse(page);
    if (!more.length) break;
    items = items.concat(more);
    next = nextOf(page);
  }
  return { first, items };
}
