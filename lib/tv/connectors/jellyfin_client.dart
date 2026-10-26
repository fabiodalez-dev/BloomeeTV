import 'dart:io';
import 'tv_http.dart';
import 'dart:convert';
import 'package:Bloomee/tv/services/tv_catalog_cache.dart';

import 'package:http/http.dart' as http;

/// Un elemento musicale di Jellyfin (album, artista o brano).
class JfItem {
  JfItem(this.raw);
  final Map<String, dynamic> raw;

  String get id => raw['Id'] as String;
  String get name => (raw['Name'] ?? '') as String;
  String get type => (raw['Type'] ?? '') as String;
  String get albumArtist =>
      (raw['AlbumArtist'] ?? (raw['Artists'] as List?)?.firstOrNull ?? '')
          as String;
  String get album => (raw['Album'] ?? '') as String;
  String? get albumId => raw['AlbumId'] as String?;
  int? get year => raw['ProductionYear'] as int?;
  int? get trackNumber => raw['IndexNumber'] as int?;
  Duration get duration =>
      Duration(microseconds: ((raw['RunTimeTicks'] ?? 0) as int) ~/ 10);

  /// Id dell'immagine: per i brani senza copertina propria si usa quella dell'album.
  String? get imageItemId {
    final tags = raw['ImageTags'] as Map?;
    if (tags != null && tags.containsKey('Primary')) return id;
    return raw['AlbumId'] as String? ?? raw['ParentId'] as String?;
  }
}

/// Client Jellyfin per la musica: accesso utente, sfoglia, ricerca, streaming.
class JellyfinClient {
  JellyfinClient(
      {required String baseUrl, this.token, this.userId, http.Client? client})
      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? tvHttpClient;

  final String baseUrl;
  String? token;
  String? userId;
  final http.Client _http;

  static const _client = 'Bloomee TV';
  static const _device = 'Chromecast';
  static const _deviceId = 'bloomee-tv';
  static const _version = '1.0';

  String get _auth =>
      'MediaBrowser Client="$_client", Device="$_device", DeviceId="$_deviceId", Version="$_version"'
      '${token != null ? ', Token="$token"' : ''}';

  Map<String, String> get _headers =>
      {'Authorization': _auth, 'Content-Type': 'application/json'};

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? q]) async {
    Future<Map<String, dynamic>> load() async {
      final r = await _http
          .get(_u(path, q), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 401 || r.statusCode == 403)
        throw const JellyfinAuthException();
      if (r.statusCode >= 300)
        throw Exception('Jellyfin $path: HTTP ${r.statusCode}');
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    }

    final key = TvCatalogCache.keyFor([baseUrl, userId, token, path, q]);
    if (q?.containsKey('SearchTerm') == true) {
      return TvCatalogCache.instance.search<Map<String, dynamic>>(
          source: 'jellyfin', key: key, load: load);
    }
    return TvCatalogCache.instance.readThrough<Map<String, dynamic>>(
        source: 'jellyfin', key: key, load: load);
  }

  /// Accesso con nome utente e password: salva token e id utente.
  Future<void> login(String username, String password) async {
    final r = await _http
        .post(_u('/Users/AuthenticateByName'),
            headers: _headers,
            body: jsonEncode({'Username': username, 'Pw': password}))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode == 401 || r.statusCode == 403)
      throw const JellyfinAuthException();
    if (r.statusCode >= 300)
      throw Exception('Accesso Jellyfin: HTTP ${r.statusCode}');
    final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    token = d['AccessToken'] as String;
    userId = (d['User'] as Map)['Id'] as String;
  }

  /// Con una chiave API (token amministratore) trova l'id dell'utente per nome.
  Future<String?> userIdByName(String name) async {
    final r = await _http
        .get(_u('/Users'), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (r.statusCode == 401 || r.statusCode == 403)
      throw const JellyfinAuthException();
    if (r.statusCode >= 300)
      throw Exception('Jellyfin /Users: HTTP ${r.statusCode}');
    final users = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    for (final u in users) {
      if ((u['Name'] as String).toLowerCase() == name.toLowerCase())
        return u['Id'] as String;
    }
    return users.isNotEmpty && name.isEmpty
        ? users.first['Id'] as String
        : null;
  }

  Future<String> serverName() async {
    final response = await _http
        .get(_u('/System/Info/Public'), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401 || response.statusCode == 403)
      throw const JellyfinAuthException();
    if (response.statusCode != 200)
      throw HttpException('Jellyfin: HTTP ${response.statusCode}');
    return (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['ServerName']
        as String;
  }

  Future<List<JfItem>> _items(Map<String, String> q) async {
    final d = await _get('/Users/$userId/Items', {
      'Recursive': 'true',
      'Fields':
          'PrimaryImageAspectRatio,ProductionYear,AlbumArtist,Artists,ParentId',
      'EnableImageTypes': 'Primary',
      ...q,
    });
    return (d['Items'] as List)
        .map((e) => JfItem(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<JfItem>> recentAlbums({int limit = 30}) => _items({
        'IncludeItemTypes': 'MusicAlbum',
        'SortBy': 'DateCreated',
        'SortOrder': 'Descending',
        'Limit': '$limit',
      });

  Future<List<JfItem>> albums(
          {int start = 0,
          int limit = 100,
          String sortBy = 'SortName',
          String? genre,
          int? year,
          String? startsWith}) =>
      _allItems({
        'IncludeItemTypes': 'MusicAlbum',
        'SortBy': sortBy,
        if (genre != null && genre.isNotEmpty) 'Genres': genre,
        if (year != null) 'Years': '$year',
        if (startsWith != null && startsWith.isNotEmpty)
          'NameStartsWith': startsWith,
      }, start: start, pageSize: limit.clamp(1, 200));

  Future<List<JfItem>> _allItems(Map<String, String> query,
      {int start = 0, int pageSize = 100}) async {
    final out = <JfItem>[];
    final seen = <String>{};
    while (true) {
      final page = await _items(
          {...query, 'StartIndex': '$start', 'Limit': '$pageSize'});
      final fresh = page.where((i) => seen.add(i.id)).toList();
      out.addAll(fresh);
      if (page.length < pageSize || fresh.isEmpty) break;
      start += page.length;
    }
    return out;
  }

  Future<List<JfItem>> randomAlbums({int limit = 20}) => _items({
        'IncludeItemTypes': 'MusicAlbum',
        'SortBy': 'Random',
        'Limit': '$limit'
      });

  Future<List<JfItem>> artists({int limit = 100}) async {
    final out = <JfItem>[];
    final seen = <String>{};
    final pageSize = limit.clamp(1, 200);
    var start = 0;
    while (true) {
      final d = await _get('/Artists/AlbumArtists', {
        'UserId': userId!,
        'SortBy': 'SortName',
        'Limit': '$pageSize',
        'StartIndex': '$start',
        'Fields': 'PrimaryImageAspectRatio'
      });
      final page = (d['Items'] as List)
          .map((e) => JfItem(Map<String, dynamic>.from(e as Map)))
          .toList();
      final fresh = page.where((i) => seen.add(i.id)).toList();
      out.addAll(fresh);
      if (page.length < pageSize || fresh.isEmpty) break;
      start += page.length;
    }
    return out;
  }

  Future<List<JfItem>> albumsOfArtist(String artistId) => _allItems({
        'IncludeItemTypes': 'MusicAlbum',
        'AlbumArtistIds': artistId,
        'SortBy': 'ProductionYear,SortName',
      });

  Future<List<JfItem>> albumTracks(String albumId) => _allItems({
        'ParentId': albumId,
        'IncludeItemTypes': 'Audio',
        'SortBy': 'ParentIndexNumber,IndexNumber,SortName',
      });

  /// Playlist order comes from the playlist endpoint, not a sorted library view.
  Future<List<JfItem>> playlistTracks(String id) async {
    final out = <JfItem>[];
    var start = 0;
    while (true) {
      final data = await _get('/Playlists/$id/Items', {
        'UserId': userId!,
        'StartIndex': '$start',
        'Limit': '100',
        'Fields': 'Artists,AlbumArtist,AlbumId',
      });
      final items = (data['Items'] as List)
          .map((v) => JfItem(Map<String, dynamic>.from(v as Map)))
          .toList();
      out.addAll(items.where((t) => t.type == 'Audio'));
      start += items.length;
      if (items.isEmpty ||
          start >= ((data['TotalRecordCount'] as int?) ?? start) ||
          start >= 10000) break;
    }
    return out;
  }

  Future<List<JfItem>> search(String term,
          {int limit = 60,
          int start = 0,
          String types = 'MusicAlbum,Audio,MusicArtist'}) =>
      _items({
        'SearchTerm': term,
        'IncludeItemTypes': types,
        'EnableTotalRecordCount': 'false',
        'StartIndex': '$start',
        'Limit': '${limit.clamp(1, 200)}',
      });

  /// URL di streaming diretto del file originale (FLAC/MP3/AAC/OGG): il motore
  /// audio dell'app (libmpv) li riproduce tutti, quindi niente transcodifica.
  /// Jellyfin 12 accetta il token in query solo come `ApiKey`.
  String streamUrl(String trackId) =>
      _u('/Audio/$trackId/stream', {'static': 'true', 'ApiKey': token!})
          .toString();

  Map<String, String> get imageHeaders => Map.unmodifiable(_headers);

  String imageUrl(String itemId, {int maxSize = 600}) => _u(
          '/Items/$itemId/Images/Primary',
          {'maxHeight': '$maxSize', 'maxWidth': '$maxSize', 'quality': '90'})
      .toString();
}

class JellyfinAuthException implements TvAuthenticationFailure {
  const JellyfinAuthException();
  @override
  String toString() => 'Credenziali Jellyfin non valide';
}
