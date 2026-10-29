// Parsing delle risposte InnerTube di YouTube Music, ripreso da Bloomee per
// webOS (webos/youtube.js). Le richieste passano dal server (/api/yt/*),
// qui si leggono solo i dati.

export function text(t) {
  if (!t || typeof t !== "object") return null;
  if (typeof t.simpleText === "string") return t.simpleText;
  if (Array.isArray(t.runs)) return t.runs.map((r) => r && r.text || "").join("");
  return null;
}

export function find(node, key) {
  if (Array.isArray(node)) {
    for (const v of node) {
      const r = find(v, key);
      if (r != null) return r;
    }
  } else if (node && typeof node === "object") {
    if (Object.prototype.hasOwnProperty.call(node, key)) return node[key];
    for (const k of Object.keys(node)) {
      const r = find(node[k], key);
      if (r != null) return r;
    }
  }
  return null;
}

// Visita in profondità; non scende dentro le chiavi in stopAt (le gestisce il chiamante).
export function walk(node, f, stopAt) {
  if (Array.isArray(node)) node.forEach((v) => walk(v, f, stopAt));
  else if (node && typeof node === "object") {
    f(node);
    for (const k of Object.keys(node)) if (!stopAt || stopAt.indexOf(k) < 0) walk(node[k], f, stopAt);
  }
}

function dig(node, path) {
  return path.reduce((n, k) => n == null ? null : n[k], node);
}

// Miniatura più grande disponibile, ridimensionata a size px: card leggere,
// copertine e banner più grandi.
export function thumb(node, size) {
  const list = find(node, "thumbnails");
  if (!Array.isArray(list) || !list.length) return null;
  let url = list[list.length - 1] && list[list.length - 1].url;
  if (typeof url !== "string") return null;
  if (url.indexOf("//") === 0) url = "https:" + url;
  size = size || 226;
  return url.replace(/=w\d+-h\d+/g, "=w" + size + "-h" + size).replace(/=s\d+/g, "=s" + size);
}

export function parseDuration(t) {
  if (typeof t !== "string" || !/^\d+(:\d+)+$/.test(t)) return null;
  return t.split(":").reduce((s, x) => s * 60 + Number(x), 0);
}

export function kindOf(browseId) {
  if (!browseId) return "other";
  if (browseId.indexOf("UC") === 0) return "artist";
  if (browseId.indexOf("MPREb") === 0) return "album";
  if (/^(VL|PL|RD|OLAK)/.test(browseId)) return "playlist";
  return "other";
}

function artistLabel(value) {
  const t = value.trim();
  return !!t && !/^(Brano|Song|Video|Episodio|Puntata|Album|Single|Singolo|EP|Playlist|Artista|Artist)$|^\d+(:\d+)+$|^\d{4}$|riproduzioni|visualizzazioni|\bviews\b|\bplays\b|ascolti|iscritti|subscribers/i.test(t);
}

function browseOf(endpoint) {
  const b = endpoint && endpoint.browseEndpoint;
  return b && typeof b.browseId === "string" ? { browseId: b.browseId, params: b.params || null } : null;
}

function searchOf(endpoint) {
  const s = endpoint && endpoint.searchEndpoint;
  return s && typeof s.query === "string" ? { query: s.query, params: s.params || null } : null;
}

export function responsive(r) {
  const cols = r.flexColumns || [];
  const runsOf = (i) => dig(cols[i], ["musicResponsiveListItemFlexColumnRenderer", "text", "runs"]) || [];
  const titleRuns = runsOf(0);
  if (!titleRuns.length) return null;
  const title = titleRuns.map((e) => e.text || "").join("");
  const videoId = dig(r, ["playlistItemData", "videoId"]) || find(r.overlay, "videoId") || dig(titleRuns[0], ["navigationEndpoint", "watchEndpoint", "videoId"]) || null;
  const nav = browseOf(r.navigationEndpoint);
  const artists = [], sub = [];
  let album = null;
  for (let c = 1; c < cols.length; c++) {
    runsOf(c).forEach((run) => {
      const t = run.text || "", b = browseOf(run.navigationEndpoint);
      if (b && b.browseId.indexOf("UC") === 0) artists.push({ name: t, id: b.browseId });
      else if (b && b.browseId.indexOf("MPREb") === 0) album = { name: t, id: b.browseId };
      sub.push(t);
    });
  }
  const subtitle = sub.join("").replace(/^\s*•\s*/, "").trim();
  if (!artists.length && videoId) {
    // Formato "Brano • Artista • 3:12": prendo l'artista dal sottotitolo.
    const a = subtitle.split(" • ").filter(artistLabel)[0];
    if (a) artists.push({ name: a, id: null });
  }
  const fixed = dig(r, ["fixedColumns", 0, "musicResponsiveListItemFixedColumnRenderer", "text"]);
  let duration = parseDuration(text(fixed));
  if (duration == null) duration = subtitle.split(" • ").map(parseDuration).filter((d) => d != null)[0];
  return {
    kind: videoId ? "song" : kindOf(nav && nav.browseId),
    title,
    subtitle,
    videoId,
    browseId: nav ? nav.browseId : null,
    params: nav ? nav.params : null,
    thumbnail: thumb(r.thumbnail),
    artists,
    album,
    duration: duration == null ? null : duration,
    row: true
  };
}

export function twoRow(r) {
  const title = text(r.title);
  if (title == null) return null;
  const videoId = dig(r, ["navigationEndpoint", "watchEndpoint", "videoId"]) || null;
  const nav = browseOf(r.navigationEndpoint);
  const runs = dig(r, ["subtitle", "runs"]) || [];
  const artists = [];
  runs.forEach((run) => {
    const b = browseOf(run.navigationEndpoint);
    if (b && b.browseId.indexOf("UC") === 0) artists.push({ name: run.text, id: b.browseId });
  });
  return {
    kind: videoId ? "song" : kindOf(nav && nav.browseId),
    title,
    subtitle: runs.map((e) => e.text || "").join(""),
    videoId,
    browseId: nav ? nav.browseId : null,
    params: nav ? nav.params : null,
    thumbnail: thumb(r.thumbnailRenderer),
    artists,
    album: null,
    duration: null
  };
}

function itemOf(c) {
  if (!c || typeof c !== "object") return null;
  if (c.musicResponsiveListItemRenderer) return responsive(c.musicResponsiveListItemRenderer);
  if (c.musicTwoRowItemRenderer) return twoRow(c.musicTwoRowItemRenderer);
  return null;
}

export function itemsOf(contents) {
  return Array.isArray(contents) ? contents.map(itemOf).filter(Boolean) : [];
}

export const itemKey = (it) => it.videoId + "|" + it.browseId + "|" + it.title;

export function flatItems(d) {
  const out = [], seen = {};
  walk(d, (m) => {
    ["musicResponsiveListItemRenderer", "musicTwoRowItemRenderer"].forEach((k) => {
      if (!m[k]) return;
      const it = k === "musicTwoRowItemRenderer" ? twoRow(m[k]) : responsive(m[k]);
      if (it && !seen[itemKey(it)]) {
        seen[itemKey(it)] = true;
        out.push(it);
      }
    });
  });
  return out;
}

// Elemento principale della scheda "Risultato migliore" nella ricerca.
function cardItem(card) {
  const runs = dig(card, ["title", "runs"]) || [];
  const endpoint = runs[0] && runs[0].navigationEndpoint || card.onTap;
  const videoId = dig(endpoint, ["watchEndpoint", "videoId"]) || null;
  const nav = browseOf(endpoint);
  if (!runs.length || !videoId && !nav) return null;
  const subRuns = dig(card, ["subtitle", "runs"]) || [];
  const artists = [];
  subRuns.forEach((run) => {
    const b = browseOf(run.navigationEndpoint);
    if (b && b.browseId.indexOf("UC") === 0) artists.push({ name: run.text, id: b.browseId });
  });
  const subtitle = text(card.subtitle) || "";
  return {
    kind: videoId ? "song" : kindOf(nav && nav.browseId),
    title: text(card.title),
    subtitle,
    videoId,
    browseId: nav ? nav.browseId : null,
    params: nav ? nav.params : null,
    thumbnail: thumb(card.thumbnail),
    artists,
    album: null,
    duration: subtitle.split(" • ").map(parseDuration).filter((d) => d != null)[0] || null
  };
}

// Sezioni (righe) di una pagina: titolo, elementi, eventuale elenco completo.
export function parseSections(d) {
  const out = [];
  walk(d, (m) => {
    const car = m.musicCarouselShelfRenderer;
    if (car) {
      const h = dig(car, ["header", "musicCarouselShelfBasicHeaderRenderer"]);
      const items = itemsOf(car.contents);
      const more = browseOf(dig(h, ["title", "runs", 0, "navigationEndpoint"])) || browseOf(dig(h, ["moreContentButton", "buttonRenderer", "navigationEndpoint"]));
      if (items.length) out.push({ title: text(h && h.title) || "", items, more, search: null, shelf: false });
    }
    const shelf = m.musicShelfRenderer;
    if (shelf) {
      const items = itemsOf(shelf.contents);
      const more = browseOf(dig(shelf, ["title", "runs", 0, "navigationEndpoint"])) || browseOf(shelf.bottomEndpoint);
      if (items.length) out.push({ title: text(shelf.title) || "", items, more, search: searchOf(shelf.bottomEndpoint), shelf: true });
    }
    const card = m.musicCardShelfRenderer;
    if (card) {
      const items = [cardItem(card)].concat(itemsOf(card.contents)).filter(Boolean);
      if (items.length) out.push({ title: "Risultato migliore", items, more: null, search: null, shelf: false });
    }
    const grid = m.gridRenderer;
    if (grid) {
      const items = itemsOf(grid.items);
      if (items.length) out.push({ title: text(dig(grid, ["header", "gridHeaderRenderer", "title"])) || "", items, more: null, search: null, shelf: false });
    }
  }, ["musicCarouselShelfRenderer", "musicShelfRenderer", "musicCardShelfRenderer", "gridRenderer"]);
  return out;
}

// Pagina successiva: i token nuovi vanno nel corpo, quelli "nextContinuationData"
// nei parametri della richiesta.
export function continuation(d) {
  const command = find(d, "continuationCommand");
  if (command && command.token) return { token: command.token, legacy: false };
  const next = find(d, "nextContinuationData");
  if (next && next.continuation) return { token: next.continuation, legacy: true };
  return null;
}

// Intestazione artista: nome, descrizione, ascoltatori mensili, iscritti, foto grande.
export function artistInfo(d) {
  const info = { name: null, description: null, monthlyListeners: null, subscribers: null, banner: null, sections: parseSections(d) };
  walk(d, (m) => {
    ["musicImmersiveHeaderRenderer", "musicVisualHeaderRenderer"].forEach((k) => {
      const h = m[k];
      if (!h || info.name != null) return;
      info.name = text(h.title);
      info.description = text(h.description);
      info.monthlyListeners = text(h.monthlyListenerCount);
      const sb = dig(h, ["subscriptionButton", "subscribeButtonRenderer"]);
      if (sb) info.subscribers = text(sb.subscriberCountText) || text(sb.longSubscriberCountText);
      info.banner = thumb(h.thumbnail, 1200);
    });
    const about = m.musicDescriptionShelfRenderer;
    if (about && !info.description) info.description = text(about.description);
  });
  return info;
}

// Intestazione di album e playlist.
export function collectionInfo(d) {
  const info = { title: "", subtitle: "", thumbnail: null, artists: [] };
  walk(d, (m) => {
    ["musicResponsiveHeaderRenderer", "musicDetailHeaderRenderer", "musicEditablePlaylistDetailHeaderRenderer"].forEach((k) => {
      const h = m[k];
      if (!h || info.title) return;
      info.title = text(h.title) || "";
      info.subtitle = [text(h.straplineTextOne), text(h.subtitle)].filter(Boolean).join(" · ");
      info.thumbnail = thumb(h.thumbnail, 544);
      // Artista dell'album: i link al canale nella riga sopra o nel sottotitolo
      // ("Album • Artista • 2006"); altrimenti il testo della riga sopra.
      (dig(h, ["straplineTextOne", "runs"]) || []).concat(dig(h, ["subtitle", "runs"]) || []).forEach((run) => {
        const b = browseOf(run.navigationEndpoint);
        if (b && b.browseId.indexOf("UC") === 0 && !info.artists.some((a) => a.id === b.browseId)) info.artists.push({ name: run.text, id: b.browseId });
      });
      if (!info.artists.length && text(h.straplineTextOne)) info.artists.push({ name: text(h.straplineTextOne), id: null });
    });
  });
  return info;
}

// Negli album i brani non hanno copertina né artista propri: uso quelli dell'album.
export function fillCollectionTracks(tracks, info, browseId) {
  const album = browseId.indexOf("MPREb") === 0;
  return tracks.filter((t) => t.videoId).map((t) => Object.assign({}, t, {
    thumbnail: t.thumbnail || info.thumbnail,
    artists: t.artists.length ? t.artists : info.artists || [],
    album: t.album || (album ? { name: info.title, id: browseId } : null)
  }));
}

export function accountName(d) {
  let name = null;
  walk(d, (m) => {
    const h = m.activeAccountHeaderRenderer;
    if (h && name == null) name = text(h.accountName);
  });
  return name;
}

export function artistNames(it) {
  return it.artists.map((a) => a.name).join(", ");
}

// Filtri della ricerca di YouTube Music (gli stessi del sito e della versione Android).
export const searchParams = {
  song: "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D",
  album: "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D",
  artist: "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D",
  playlist: "EgeKAQQoADgBagoQAxAEEAoQCRAF"
};

export function searchPage(d) {
  return { items: flatItems(d), next: continuation(d) };
}

// Coda "radio" di un brano (endpoint next): i brani correlati da accodare.
export function radio(d) {
  const out = [], seen = {};
  walk(d, (m) => {
    const r = m.playlistPanelVideoRenderer;
    if (!r || !r.videoId || seen[r.videoId]) return;
    seen[r.videoId] = true;
    const runs = dig(r, ["longBylineText", "runs"]) || [];
    const artists = [];
    let album = null;
    runs.forEach((run) => {
      const b = browseOf(run.navigationEndpoint);
      if (b && b.browseId.indexOf("UC") === 0) artists.push({ name: run.text, id: b.browseId });
      else if (b && b.browseId.indexOf("MPREb") === 0) album = { name: run.text, id: b.browseId };
    });
    const byline = text(r.shortBylineText) || "";
    out.push({
      kind: "song",
      title: text(r.title) || "",
      subtitle: text(r.longBylineText) || byline,
      videoId: r.videoId,
      browseId: null,
      params: null,
      thumbnail: thumb(r.thumbnail),
      artists: artists.length ? artists : byline ? [{ name: byline, id: null }] : [],
      album,
      duration: parseDuration(text(r.lengthText))
    });
  });
  return out;
}

// Suggerimenti mentre si scrive: testi completati e risultati diretti.
export function suggestions(d) {
  const queries = [];
  walk(d, (m) => {
    const s = m.searchSuggestionRenderer;
    const q = s && dig(s, ["navigationEndpoint", "searchEndpoint", "query"]);
    if (q && queries.indexOf(q) < 0) queries.push(q);
  });
  return { queries, items: flatItems(d).slice(0, 6) };
}

// Filtri ("Energia pura", "Relax"…) in cima alla Home.
export function chips(d) {
  const out = [];
  walk(d, (m) => {
    const c = m.chipCloudChipRenderer;
    const b = c && browseOf(c.navigationEndpoint);
    if (b && b.params) out.push({ title: text(c.text) || "", browseId: b.browseId, params: b.params });
  });
  return out;
}

// Pulsanti di "Mood e generi": titolo, colore della striscia, pagina.
export function moods(d) {
  const groups = [];
  walk(d, (m) => {
    const grid = m.gridRenderer;
    if (!grid) return;
    const items = (grid.items || []).map((i) => i.musicNavigationButtonRenderer).filter(Boolean).map((b) => {
      const nav = browseOf(dig(b, ["clickCommand"]));
      const argb = dig(b, ["solid", "leftStripeColor"]);
      return nav && {
        title: text(b.buttonText) || "",
        browseId: nav.browseId,
        params: nav.params,
        color: typeof argb === "number" ? "#" + (argb & 0xffffff).toString(16).padStart(6, "0") : null
      };
    }).filter(Boolean);
    if (items.length) groups.push({ title: text(dig(grid, ["header", "gridHeaderRenderer", "title"])) || "", items });
  }, ["gridRenderer"]);
  return groups;
}

// Pulsanti dell'intestazione artista: casuale e mix.
export function artistActions(d) {
  const h = find(d, "musicImmersiveHeaderRenderer") || find(d, "musicVisualHeaderRenderer") || {};
  const play = dig(h, ["playButton", "buttonRenderer", "navigationEndpoint", "watchEndpoint"]);
  const mix = dig(h, ["startRadioButton", "buttonRenderer", "navigationEndpoint", "watchPlaylistEndpoint"]);
  return {
    shuffle: play && play.playlistId ? { videoId: play.videoId || null, playlistId: play.playlistId, params: play.params || null } : null,
    mix: mix && mix.playlistId ? { playlistId: mix.playlistId, params: mix.params || null } : null
  };
}

// Righe aggiuntive dell'intestazione di album e playlist (brani, durata, descrizione).
export function collectionExtra(d) {
  const h = find(d, "musicResponsiveHeaderRenderer") || find(d, "musicDetailHeaderRenderer") || {};
  const desc = find(h, "musicDescriptionShelfRenderer");
  return {
    stats: text(h.secondSubtitle) || "",
    description: desc ? text(desc.description) : text(h.description) || ""
  };
}

// Testo dal pannello "Testo" del brano: prima l'id della pagina, poi il testo.
export function lyricsBrowseId(d) {
  let id = null;
  walk(d, (m) => {
    const b = m.tabRenderer && browseOf(m.tabRenderer.endpoint);
    if (b && b.browseId.indexOf("MPLY") === 0 && !id) id = b.browseId;
  });
  return id;
}

export function plainLyrics(d) {
  const shelf = find(d, "musicDescriptionShelfRenderer");
  if (!shelf) return null;
  const body = text(shelf.description);
  if (!body) return null;
  return {
    source: (text(shelf.footer) || "YouTube Music").replace(/^Fonte:\s*/i, ""),
    synced: false,
    words: false,
    lines: body.split("\n").map((l) => ({ t: null, end: null, text: l }))
  };
}
