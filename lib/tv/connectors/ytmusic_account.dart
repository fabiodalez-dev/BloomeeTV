import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Id del plugin ytmusic di Bloomee: i brani trovati qui si riproducono con
/// lo stesso plugin (`content-resolver.bloomfactory.ytmusic::<videoId>`).
const String kYtMusicPluginId = 'content-resolver.bloomfactory.ytmusic';

/// Un elemento di YouTube Music (brano, album, playlist o artista).
class YtItem {
  YtItem({
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.videoId,
    this.browseId,
    this.thumbnail,
    this.artists = const [],
    this.album,
    this.duration,
  });

  /// 'song', 'album', 'playlist', 'artist'
  final String kind;
  final String title;
  final String subtitle;
  final String? videoId;
  final String? browseId;
  final String? thumbnail;
  final List<YtRef> artists;
  final YtRef? album;
  final Duration? duration;

  String get artistNames => artists.map((a) => a.name).join(', ');
}

class YtRef {
  const YtRef(this.name, this.id);
  final String name;
  final String? id;
}

/// Una sezione (riga) di YouTube Music: titolo + elementi.
class YtSection {
  YtSection(this.title, this.items, {this.moreBrowseId, this.moreParams});
  final String title;
  final List<YtItem> items;
  /// Pagina con l'elenco completo (tutti gli album, tutti i brani…).
  final String? moreBrowseId;
  final String? moreParams;
}

/// Dati extra dell'artista: descrizione completa, ascoltatori mensili,
/// iscritti, foto grande.
class YtArtistInfo {
  YtArtistInfo({this.name, this.description, this.monthlyListeners, this.subscribers, this.banner, this.sections = const []});
  final String? name;
  final String? description;
  final String? monthlyListeners;
  final String? subscribers;
  final String? banner;
  final List<YtSection> sections;
}

/// Client InnerTube di YouTube Music (lo stesso protocollo del sito web e di
/// Echo Music). Con i cookie dell'account firma le richieste (SAPISIDHASH) e
/// ottiene cronologia, Mi piace, playlist e home personalizzata.
class YtMusicClient {
  YtMusicClient({this.cookie = '', this.visitorData = '', this.dataSyncId = '', http.Client? client})
      : _http = client ?? http.Client();

  final String cookie;
  final String visitorData;
  final String dataSyncId;
  final http.Client _http;

  static const _origin = 'https://music.youtube.com';
  static const _clientVersion = '1.20250310.01.00';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  bool get loggedIn => _sapisid != null;

  String? get _sapisid {
    for (final part in cookie.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length < 2) continue;
      if (kv[0] == 'SAPISID' || kv[0] == '__Secure-3PAPISID') return kv.sublist(1).join('=');
    }
    return null;
  }

  /// "Brand account": DATASYNC_ID è "idDelegato||idUtente".
  String? get _onBehalfOf {
    final d = dataSyncId.split('||').first;
    return d.isEmpty ? null : d;
  }

  Map<String, String> _headers() {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': _ua,
      'Origin': _origin,
      'X-Origin': _origin,
      'Referer': '$_origin/',
      'X-Goog-AuthUser': '0',
      'X-YouTube-Client-Name': '67',
      'X-YouTube-Client-Version': _clientVersion,
    };
    if (visitorData.isNotEmpty) h['X-Goog-Visitor-Id'] = visitorData;
    final sap = _sapisid;
    if (sap != null) {
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final hash = sha1.convert(utf8.encode('$ts $sap $_origin')).toString();
      h['Cookie'] = cookie;
      h['Authorization'] = 'SAPISIDHASH ${ts}_$hash';
    }
    return h;
  }

  Map<String, dynamic> _context() => {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': _clientVersion,
          'hl': 'it',
          'gl': 'IT',
          if (visitorData.isNotEmpty) 'visitorData': visitorData,
        },
        if (_onBehalfOf != null) 'user': {'onBehalfOfUser': _onBehalfOf},
      };

  Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> body) async {
    final r = await _http
        .post(Uri.parse('$_origin/youtubei/v1/$endpoint?prettyPrint=false'),
            headers: _headers(), body: jsonEncode({'context': _context(), ...body}))
        .timeout(const Duration(seconds: 25));
    if (r.statusCode == 401 || r.statusCode == 403) throw const YtAuthException();
    if (r.statusCode >= 300) throw Exception('YouTube Music $endpoint: HTTP ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> browse(String browseId, {Map<String, dynamic>? extra}) =>
      _post('browse', {'browseId': browseId, ...?extra});

  // ── API di alto livello ──────────────────────────────────────────────

  /// Nome dell'account collegato.
  Future<String?> accountName() async {
    final d = await _post('account/account_menu', {});
    String? name;
    _walk(d, (m) {
      final h = m['activeAccountHeaderRenderer'];
      if (h is Map && name == null) name = _text(h['accountName']);
    });
    return name;
  }

  Future<List<YtSection>> home() async => parseSections(await browse('FEmusic_home'));

  Future<List<YtItem>> history() async => _flatItems(await browse('FEmusic_history'));

  Future<List<YtItem>> likedSongs() async => _flatItems(await browse('VLLM'));

  Future<List<YtItem>> libraryPlaylists() async =>
      _flatItems(await browse('FEmusic_liked_playlists')).where((i) => i.browseId != null).toList();

  Future<List<YtItem>> libraryAlbums() async => _flatItems(await browse('FEmusic_liked_albums'));

  Future<List<YtItem>> subscribedArtists() async =>
      _flatItems(await browse('FEmusic_library_corpus_artists')).where((i) => i.browseId?.startsWith('UC') ?? false).toList();

  /// Brani di una playlist o di un album (browseId VL…/MPREb…).
  Future<({String title, String? subtitle, String? thumbnail, List<YtItem> tracks})> collection(String browseId) async {
    final d = await browse(browseId);
    String title = '';
    String? subtitle;
    String? thumb;
    _walk(d, (m) {
      for (final k in const ['musicResponsiveHeaderRenderer', 'musicDetailHeaderRenderer', 'musicEditablePlaylistDetailHeaderRenderer']) {
        final h = m[k];
        if (h is Map && title.isEmpty) {
          title = _text(h['title']) ?? '';
          subtitle = [_text(h['straplineTextOne']), _text(h['subtitle'])].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
          thumb = _thumb(h['thumbnail']);
        }
      }
    });
    final tracks = _flatItems(d).where((i) => i.videoId != null).toList();
    // Negli album i brani non hanno copertina propria: uso quella dell'album.
    final fixed = [
      for (final t in tracks)
        t.thumbnail != null
            ? t
            : YtItem(
                kind: t.kind,
                title: t.title,
                subtitle: t.subtitle,
                videoId: t.videoId,
                thumbnail: thumb,
                artists: t.artists.isEmpty && subtitle != null ? [YtRef(subtitle!.split(' · ').last, null)] : t.artists,
                album: t.album ?? (browseId.startsWith('MPREb') ? YtRef(title, browseId) : null),
                duration: t.duration,
              ),
    ];
    return (title: title, subtitle: subtitle, thumbnail: thumb, tracks: fixed);
  }

  /// Pagina artista (funziona anche senza account).
  Future<YtArtistInfo> artist(String channelId) async {
    final d = await browse(channelId);
    String? name, desc, listeners, subs, banner;
    _walk(d, (m) {
      for (final k in const ['musicImmersiveHeaderRenderer', 'musicVisualHeaderRenderer']) {
        final h = m[k];
        if (h is Map && name == null) {
          name = _text(h['title']);
          desc = _text(h['description']);
          listeners = _text(h['monthlyListenerCount']);
          final sb = h['subscriptionButton']?['subscribeButtonRenderer'];
          if (sb is Map) subs = _text(sb['subscriberCountText']) ?? _text(sb['longSubscriberCountText']);
          banner = _thumb(h['thumbnail'], best: true);
        }
      }
      final about = m['musicDescriptionShelfRenderer'];
      if (about is Map && (desc == null || desc!.isEmpty)) desc = _text(about['description']);
    });
    return YtArtistInfo(
      name: name,
      description: desc,
      monthlyListeners: listeners,
      subscribers: subs,
      banner: banner,
      sections: parseSections(d),
    );
  }

  /// Filtri della ricerca di YouTube Music (gli stessi del sito).
  static const searchParams = {
    'song': 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D',
    'album': 'EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D',
    'artist': 'EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D',
    'playlist': 'EgeKAQQoADgBagoQAxAEEAoQCRAF',
  };

  /// Ricerca senza filtro: le sezioni come sul sito (Brani, Album, Artisti…).
  Future<List<YtSection>> searchAll(String query) async => parseSections(await _post('search', {'query': query}));

  /// Ricerca filtrata per tipo ('song', 'album', 'artist', 'playlist').
  Future<List<YtItem>> searchType(String query, String kind) async =>
      _flatItems(await _post('search', {'query': query, 'params': searchParams[kind]}));

  static (String, String?)? _browseOf(dynamic endpoint) {
    final b = endpoint is Map ? endpoint['browseEndpoint'] : null;
    if (b is! Map || b['browseId'] is! String) return null;
    return (b['browseId'] as String, b['params'] as String?);
  }

  /// Elenco completo di una pagina (discografia, playlist dei brani…),
  /// seguendo le pagine successive fino a [maxPages].
  Future<List<YtItem>> browseAll(String browseId, {String? params, int maxPages = 20}) async {
    final out = <YtItem>[];
    final seen = <String>{};
    void add(List<YtItem> items) {
      for (final i in items) {
        if (seen.add('${i.videoId}|${i.browseId}|${i.title}')) out.add(i);
      }
    }
    var d = await browse(browseId, extra: {if (params != null) 'params': params});
    for (var page = 0; page < maxPages; page++) {
      add(_flatItems(d));
      final token = _find(d, 'continuationCommand')?['token'] as String? ??
          _find(d, 'nextContinuationData')?['continuation'] as String?;
      if (token == null) break;
      d = await _post('browse', {'continuation': token});
    }
    return out;
  }

  /// Cerca il canale di un artista per nome (quando l'id del plugin non è un UC…).
  Future<String?> findArtistChannel(String name) async {
    final d = await _post('search', {'query': name, 'params': 'EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D'});
    final items = _flatItems(d).where((i) => i.browseId?.startsWith('UC') ?? false).toList();
    final n = name.toLowerCase().trim();
    for (final i in items) {
      if (i.title.toLowerCase().trim() == n) return i.browseId;
    }
    return items.isNotEmpty ? items.first.browseId : null;
  }

  // ── Parsing ──────────────────────────────────────────────────────────

  List<YtSection> parseSections(Map<String, dynamic> d) {
    final out = <YtSection>[];
    _walk(d, (m) {
      final car = m['musicCarouselShelfRenderer'];
      if (car is Map) {
        final h = car['header']?['musicCarouselShelfBasicHeaderRenderer'];
        final title = _text(h?['title']) ?? '';
        final items = _itemsOf(car['contents']);
        final more = _browseOf(h?['title']?['runs']?[0]?['navigationEndpoint']) ??
            _browseOf(h?['moreContentButton']?['buttonRenderer']?['navigationEndpoint']);
        if (items.isNotEmpty) out.add(YtSection(title, items, moreBrowseId: more?.$1, moreParams: more?.$2));
      }
      final shelf = m['musicShelfRenderer'];
      if (shelf is Map) {
        final items = _itemsOf(shelf['contents']);
        final more = _browseOf(shelf['title']?['runs']?[0]?['navigationEndpoint']) ?? _browseOf(shelf['bottomEndpoint']);
        if (items.isNotEmpty) {
          out.add(YtSection(_text(shelf['title']) ?? '', items, moreBrowseId: more?.$1, moreParams: more?.$2));
        }
      }
    }, stopAt: const {'musicCarouselShelfRenderer', 'musicShelfRenderer'});
    return out;
  }

  List<YtItem> _flatItems(Map<String, dynamic> d) {
    final out = <YtItem>[];
    final seen = <String>{};
    _walk(d, (m) {
      for (final k in const ['musicResponsiveListItemRenderer', 'musicTwoRowItemRenderer']) {
        final r = m[k];
        if (r is Map) {
          final it = k == 'musicTwoRowItemRenderer' ? _twoRow(r) : _responsive(r);
          if (it != null && seen.add('${it.videoId}|${it.browseId}|${it.title}')) out.add(it);
        }
      }
    });
    return out;
  }

  List<YtItem> _itemsOf(dynamic contents) {
    if (contents is! List) return const [];
    final out = <YtItem>[];
    for (final c in contents) {
      if (c is! Map) continue;
      final r1 = c['musicResponsiveListItemRenderer'];
      final r2 = c['musicTwoRowItemRenderer'];
      final it = r1 is Map ? _responsive(r1) : (r2 is Map ? _twoRow(r2) : null);
      if (it != null) out.add(it);
    }
    return out;
  }

  YtItem? _responsive(Map r) {
    final cols = (r['flexColumns'] as List?) ?? const [];
    List runsOf(int i) => i < cols.length
        ? ((cols[i]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List?) ?? const [])
        : const [];
    final titleRuns = runsOf(0);
    if (titleRuns.isEmpty) return null;
    final title = titleRuns.map((e) => e['text']).join();
    final videoId = r['playlistItemData']?['videoId'] as String? ??
        _find(r['overlay'], 'videoId') as String? ??
        titleRuns.first['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
    final browseId = r['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
    final artists = <YtRef>[];
    YtRef? album;
    final sub = <String>[];
    for (var c = 1; c < cols.length; c++) {
      for (final run in runsOf(c)) {
        final text = run['text'] as String? ?? '';
        final bid = run['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
        if (bid != null && bid.startsWith('UC')) {
          artists.add(YtRef(text, bid));
        } else if (bid != null && bid.startsWith('MPREb')) {
          album = YtRef(text, bid);
        }
        sub.add(text);
      }
    }
    final subtitle = sub.join().replaceAll(RegExp(r'^\s*•\s*'), '').trim();
    if (artists.isEmpty && videoId != null) {
      // Formato "Brano • Artista • 3:12": prendo l'artista dal sottotitolo.
      final parts = subtitle.split(' • ');
      final a = parts.firstWhere((p) => !RegExp(r'^(Brano|Song|Video|Episodio)$').hasMatch(p), orElse: () => '');
      if (a.isNotEmpty) artists.add(YtRef(a, null));
    }
    Duration? dur;
    final fixed = r['fixedColumns'] as List?;
    final dText = fixed != null && fixed.isNotEmpty
        ? _text(fixed[0]?['musicResponsiveListItemFixedColumnRenderer']?['text'])
        : null;
    dur = _parseDuration(dText);
    return YtItem(
      kind: videoId != null ? 'song' : _kindOf(browseId),
      title: title,
      subtitle: subtitle,
      videoId: videoId,
      browseId: browseId,
      thumbnail: _thumb(r['thumbnail']),
      artists: artists,
      album: album,
      duration: dur,
    );
  }

  YtItem? _twoRow(Map r) {
    final title = _text(r['title']);
    if (title == null) return null;
    final nav = r['navigationEndpoint'];
    final videoId = nav?['watchEndpoint']?['videoId'] as String?;
    final browseId = nav?['browseEndpoint']?['browseId'] as String?;
    final subRuns = (r['subtitle']?['runs'] as List?) ?? const [];
    final artists = <YtRef>[];
    for (final run in subRuns) {
      final bid = run['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
      if (bid != null && bid.startsWith('UC')) artists.add(YtRef(run['text'] as String, bid));
    }
    return YtItem(
      kind: videoId != null ? 'song' : _kindOf(browseId),
      title: title,
      subtitle: subRuns.map((e) => e['text']).join(),
      videoId: videoId,
      browseId: browseId,
      thumbnail: _thumb(r['thumbnailRenderer']),
      artists: artists,
    );
  }

  static String _kindOf(String? browseId) {
    if (browseId == null) return 'other';
    if (browseId.startsWith('UC')) return 'artist';
    if (browseId.startsWith('MPREb')) return 'album';
    if (browseId.startsWith('VL') || browseId.startsWith('PL') || browseId.startsWith('RD')) return 'playlist';
    return 'other';
  }

  static Duration? _parseDuration(String? t) {
    if (t == null || !RegExp(r'^\d+(:\d+)+$').hasMatch(t)) return null;
    final p = t.split(':').map(int.parse).toList();
    var s = 0;
    for (final x in p) {
      s = s * 60 + x;
    }
    return Duration(seconds: s);
  }

  static String? _text(dynamic t) {
    if (t is! Map) return null;
    if (t['simpleText'] is String) return t['simpleText'] as String;
    final runs = t['runs'];
    if (runs is List) return runs.map((e) => e is Map ? (e['text'] ?? '') : '').join();
    return null;
  }

  /// Miniatura più grande disponibile, ingrandita a 544px (o 1200 per i banner).
  static String? _thumb(dynamic node, {bool best = false}) {
    final list = _find(node, 'thumbnails');
    if (list is! List || list.isEmpty) return null;
    var url = (list.last as Map)['url'] as String?;
    if (url == null) return null;
    if (url.startsWith('//')) url = 'https:$url';
    final size = best ? 1200 : 544;
    return url.replaceAll(RegExp(r'=w\d+-h\d+'), '=w$size-h$size').replaceAll(RegExp(r'=s\d+'), '=s$size');
  }

  static dynamic _find(dynamic node, String key) {
    if (node is Map) {
      if (node.containsKey(key)) return node[key];
      for (final v in node.values) {
        final r = _find(v, key);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _find(v, key);
        if (r != null) return r;
      }
    }
    return null;
  }

  /// Visita in profondità; non scende dentro le chiavi in [stopAt] (le
  /// gestisce il chiamante).
  static void _walk(dynamic node, void Function(Map m) f, {Set<String> stopAt = const {}}) {
    if (node is Map) {
      f(node);
      for (final e in node.entries) {
        if (stopAt.contains(e.key)) continue;
        _walk(e.value, f, stopAt: stopAt);
      }
    } else if (node is List) {
      for (final v in node) {
        _walk(v, f, stopAt: stopAt);
      }
    }
  }
}

class YtAuthException implements Exception {
  const YtAuthException();
  @override
  String toString() => 'Sessione YouTube scaduta: accedi di nuovo da Impostazioni';
}
