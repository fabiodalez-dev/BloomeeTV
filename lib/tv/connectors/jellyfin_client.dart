import 'dart:convert';

import 'package:http/http.dart' as http;

/// Un elemento musicale di Jellyfin (album, artista o brano).
class JfItem {
  JfItem(this.raw);
  final Map<String, dynamic> raw;

  String get id => raw['Id'] as String;
  String get name => (raw['Name'] ?? '') as String;
  String get type => (raw['Type'] ?? '') as String;
  String get albumArtist =>
      (raw['AlbumArtist'] ?? (raw['Artists'] as List?)?.firstOrNull ?? '') as String;
  String get album => (raw['Album'] ?? '') as String;
  String? get albumId => raw['AlbumId'] as String?;
  int? get year => raw['ProductionYear'] as int?;
  int? get trackNumber => raw['IndexNumber'] as int?;
  Duration get duration => Duration(microseconds: ((raw['RunTimeTicks'] ?? 0) as int) ~/ 10);

  /// Id dell'immagine: per i brani senza copertina propria si usa quella dell'album.
  String? get imageItemId {
    final tags = raw['ImageTags'] as Map?;
    if (tags != null && tags.containsKey('Primary')) return id;
    return raw['AlbumId'] as String? ?? raw['ParentId'] as String?;
  }
}

/// Client Jellyfin per la musica: accesso utente, sfoglia, ricerca, streaming.
class JellyfinClient {
  JellyfinClient({required String baseUrl, this.token, this.userId, http.Client? client})
      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();

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

  Map<String, String> get _headers => {'Authorization': _auth, 'Content-Type': 'application/json'};

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? q]) async {
    final r = await _http.get(_u(path, q), headers: _headers).timeout(const Duration(seconds: 20));
    if (r.statusCode == 401) throw const JellyfinAuthException();
    if (r.statusCode >= 300) throw Exception('Jellyfin $path: HTTP ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// Accesso con nome utente e password: salva token e id utente.
  Future<void> login(String username, String password) async {
    final r = await _http
        .post(_u('/Users/AuthenticateByName'),
            headers: _headers, body: jsonEncode({'Username': username, 'Pw': password}))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode == 401) throw const JellyfinAuthException();
    if (r.statusCode >= 300) throw Exception('Accesso Jellyfin: HTTP ${r.statusCode}');
    final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    token = d['AccessToken'] as String;
    userId = (d['User'] as Map)['Id'] as String;
  }

  /// Con una chiave API (token amministratore) trova l'id dell'utente per nome.
  Future<String?> userIdByName(String name) async {
    final r = await _http.get(_u('/Users'), headers: _headers).timeout(const Duration(seconds: 20));
    if (r.statusCode == 401) throw const JellyfinAuthException();
    if (r.statusCode >= 300) throw Exception('Jellyfin /Users: HTTP ${r.statusCode}');
    final users = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    for (final u in users) {
      if ((u['Name'] as String).toLowerCase() == name.toLowerCase()) return u['Id'] as String;
    }
    return users.isNotEmpty && name.isEmpty ? users.first['Id'] as String : null;
  }

  Future<String> serverName() async => (await _get('/System/Info/Public'))['ServerName'] as String;

  Future<List<JfItem>> _items(Map<String, String> q) async {
    final d = await _get('/Users/$userId/Items', {
      'Recursive': 'true',
      'Fields': 'PrimaryImageAspectRatio,ProductionYear,AlbumArtist,Artists,ParentId',
      'EnableImageTypes': 'Primary',
      ...q,
    });
    return (d['Items'] as List).map((e) => JfItem(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<List<JfItem>> recentAlbums({int limit = 30}) => _items({
        'IncludeItemTypes': 'MusicAlbum',
        'SortBy': 'DateCreated',
        'SortOrder': 'Descending',
        'Limit': '$limit',
      });

  Future<List<JfItem>> albums({int start = 0, int limit = 60, String sortBy = 'SortName'}) => _items({
        'IncludeItemTypes': 'MusicAlbum',
        'SortBy': sortBy,
        'StartIndex': '$start',
        'Limit': '$limit',
      });

  Future<List<JfItem>> randomAlbums({int limit = 20}) =>
      _items({'IncludeItemTypes': 'MusicAlbum', 'SortBy': 'Random', 'Limit': '$limit'});

  Future<List<JfItem>> artists({int limit = 60}) async {
    final d = await _get('/Artists/AlbumArtists', {
      'UserId': userId!,
      'SortBy': 'SortName',
      'Limit': '$limit',
      'Fields': 'PrimaryImageAspectRatio',
    });
    return (d['Items'] as List).map((e) => JfItem(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<List<JfItem>> albumsOfArtist(String artistId) => _items({
        'IncludeItemTypes': 'MusicAlbum',
        'AlbumArtistIds': artistId,
        'SortBy': 'ProductionYear,SortName',
      });

  Future<List<JfItem>> albumTracks(String albumId) => _items({
        'ParentId': albumId,
        'IncludeItemTypes': 'Audio',
        'SortBy': 'ParentIndexNumber,IndexNumber,SortName',
      });

  Future<List<JfItem>> search(String term, {int limit = 30}) => _items({
        'SearchTerm': term,
        'IncludeItemTypes': 'MusicAlbum,Audio,MusicArtist',
        'Limit': '$limit',
      });

  /// URL di streaming diretto del file originale (FLAC/MP3/AAC/OGG): il motore
  /// audio dell'app (libmpv) li riproduce tutti, quindi niente transcodifica.
  /// Jellyfin 12 accetta il token in query solo come `ApiKey`.
  String streamUrl(String trackId) =>
      _u('/Audio/$trackId/stream', {'static': 'true', 'ApiKey': token!}).toString();

  String imageUrl(String itemId, {int maxSize = 600}) =>
      _u('/Items/$itemId/Images/Primary', {'maxHeight': '$maxSize', 'maxWidth': '$maxSize', 'quality': '90'})
          .toString();
}

class JellyfinAuthException implements Exception {
  const JellyfinAuthException();
  @override
  String toString() => 'Credenziali Jellyfin non valide';
}
