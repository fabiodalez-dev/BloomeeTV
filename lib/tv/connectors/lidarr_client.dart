import 'dart:convert';

import 'package:http/http.dart' as http;

/// Esito di una richiesta "Scarica questo album".
enum LidarrRequestStatus { requested, alreadyPresent, alreadyMonitored, notFound, error }

class LidarrRequestResult {
  const LidarrRequestResult(this.status, {this.albumTitle, this.artistName, this.year, this.message});
  final LidarrRequestStatus status;
  final String? albumTitle;
  final String? artistName;
  final int? year;
  final String? message;
}

/// Client minimale per l'API v1 di Lidarr.
///
/// "Scarica questo album": cerca l'album per artista + titolo, aggiunge
/// l'artista SENZA monitorarne la discografia, monitora solo quell'album e
/// lancia la ricerca. Lidarr poi lo scarica e lo organizza in
/// Artista/Album (Anno), dove Jellyfin lo trova.
class LidarrClient {
  LidarrClient({required String baseUrl, required this.apiKey, http.Client? client})
      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final http.Client _http;

  Map<String, String> get _headers => {'X-Api-Key': apiKey, 'Content-Type': 'application/json'};

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl/api/v1$path').replace(queryParameters: q);

  Future<dynamic> _get(String path, [Map<String, String>? q]) async {
    final r = await _http.get(_u(path, q), headers: _headers).timeout(const Duration(seconds: 30));
    if (r.statusCode >= 300) throw Exception('Lidarr $path: HTTP ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<dynamic> _send(String method, String path, Object body) async {
    final req = http.Request(method, _u(path))
      ..headers.addAll(_headers)
      ..body = jsonEncode(body);
    final r = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 60)));
    if (r.statusCode >= 300) {
      throw Exception('Lidarr $path: HTTP ${r.statusCode} ${r.body.length > 200 ? r.body.substring(0, 200) : r.body}');
    }
    return r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Verifica raggiungibilità e chiave.
  Future<String> ping() async {
    final s = await _get('/system/status');
    return 'Lidarr ${s['version']}';
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
      .replaceAll(RegExp(r'(remaster(ed)?|deluxe|edition|expanded|anniversary)'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  /// Punteggio di somiglianza 0..1 tra due stringhe normalizzate (token in comune).
  static double _score(String a, String b) {
    final ta = _norm(a).split(' ').where((t) => t.isNotEmpty).toSet();
    final tb = _norm(b).split(' ').where((t) => t.isNotEmpty).toSet();
    if (ta.isEmpty || tb.isEmpty) return 0;
    return ta.intersection(tb).length / ta.union(tb).length;
  }

  /// Sceglie il risultato migliore: artista quasi uguale, titolo più simile,
  /// a parità preferisce l'album "originale" (data più vecchia).
  Map<String, dynamic>? _best(List results, String artist, String album) {
    Map<String, dynamic>? best;
    var bestScore = 0.0;
    for (final raw in results) {
      final r = Map<String, dynamic>.from(raw as Map);
      final a = (r['artist'] as Map?)?['artistName']?.toString() ?? '';
      final sa = _score(a, artist);
      if (sa < 0.5) continue;
      final st = _score(r['title']?.toString() ?? '', album);
      // Titolo troppo diverso (es. "Atto II" contro l'album base): meglio
      // "non trovato" che scaricare l'album sbagliato.
      if (st < 0.6) continue;
      final s = sa * 0.4 + st * 0.6;
      if (s > bestScore) {
        bestScore = s;
        best = r;
      }
    }
    return bestScore >= 0.55 ? best : null;
  }

  Future<void> _waitArtistRefresh() async {
    for (var i = 0; i < 40; i++) {
      final cmds = await _get('/command') as List;
      final busy = cmds.any((c) =>
          (c['name'] == 'RefreshArtist' || c['name'] == 'AddArtist') &&
          (c['status'] == 'started' || c['status'] == 'queued'));
      if (!busy) return;
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  /// Anteprima per la conferma: trova l'album senza aggiungere nulla.
  Future<LidarrRequestResult> findAlbum({required String artist, required String album}) async {
    try {
      final results = await _get('/album/lookup', {'term': '$artist $album'}) as List;
      final hit = _best(results, artist, album);
      if (hit == null) return const LidarrRequestResult(LidarrRequestStatus.notFound);
      return LidarrRequestResult(
        LidarrRequestStatus.requested,
        albumTitle: hit['title']?.toString(),
        artistName: (hit['artist'] as Map)['artistName']?.toString(),
        year: int.tryParse((hit['releaseDate']?.toString() ?? '').padRight(4).substring(0, 4).trim()),
      );
    } catch (e) {
      return LidarrRequestResult(LidarrRequestStatus.error, message: e.toString());
    }
  }

  Future<LidarrRequestResult> requestAlbum({required String artist, required String album}) async {
    try {
      final results = await _get('/album/lookup', {'term': '$artist $album'}) as List;
      final hit = _best(results, artist, album);
      if (hit == null) return const LidarrRequestResult(LidarrRequestStatus.notFound);
      final title = hit['title']?.toString();
      final artistName = (hit['artist'] as Map)['artistName']?.toString();
      final year = int.tryParse((hit['releaseDate']?.toString() ?? '').padRight(4).substring(0, 4).trim());

      final roots = await _get('/rootfolder') as List;
      final qps = await _get('/qualityprofile') as List;
      final mps = await _get('/metadataprofile') as List;
      final root = roots.isNotEmpty ? roots.first['path'] : null;
      if (root == null || qps.isEmpty || mps.isEmpty) {
        return const LidarrRequestResult(LidarrRequestStatus.error, message: 'Lidarr senza cartella o profili');
      }
      final mp = mps.firstWhere((m) => m['name'] != 'None', orElse: () => mps.first);

      // Artista: se manca lo aggiungo senza monitorare la discografia.
      final foreignArtistId = (hit['artist'] as Map)['foreignArtistId'];
      final artists = await _get('/artist') as List;
      var existingArtist = artists.cast<Map>().where((a) => a['foreignArtistId'] == foreignArtistId).firstOrNull;
      existingArtist ??= await _send('POST', '/artist', {
        ...Map<String, dynamic>.from(hit['artist'] as Map),
        'rootFolderPath': root,
        'qualityProfileId': qps.first['id'],
        'metadataProfileId': mp['id'],
        'monitored': true,
        'monitorNewItems': 'none',
        'addOptions': {'monitor': 'none', 'searchForMissingAlbums': false},
      }) as Map;

      // Album: dopo l'aggiunta dell'artista Lidarr lo conosce già; lo monitoro e lo cerco.
      Map? existing;
      for (var i = 0; i < 10 && existing == null; i++) {
        final albums = await _get('/album', {'artistId': '${existingArtist['id']}'}) as List;
        existing = albums.cast<Map>().where((a) => a['foreignAlbumId'] == hit['foreignAlbumId']).firstOrNull;
        if (existing == null) await Future.delayed(const Duration(seconds: 2));
      }
      if (existing == null) {
        existing = await _send('POST', '/album', {
          ...hit,
          'artistId': existingArtist['id'],
          'monitored': true,
          'addOptions': {'searchForNewAlbum': true},
        }) as Map;
        return LidarrRequestResult(LidarrRequestStatus.requested, albumTitle: title, artistName: artistName, year: year);
      }
      final stats = existing['statistics'] as Map?;
      if ((stats?['trackFileCount'] ?? 0) > 0 && stats?['trackFileCount'] == stats?['trackCount']) {
        return LidarrRequestResult(LidarrRequestStatus.alreadyPresent, albumTitle: title, artistName: artistName, year: year);
      }
      final wasMonitored = existing['monitored'] == true;
      // Un artista appena aggiunto viene aggiornato da Lidarr in background
      // con "monitor none": se monitoro prima che finisca, l'aggiornamento
      // lo annulla. Aspetto la fine (max ~2 min), poi monitoro e verifico.
      await _waitArtistRefresh();
      for (var i = 0; i < 3; i++) {
        await _send('PUT', '/album/monitor', {'albumIds': [existing['id']], 'monitored': true});
        final check = await _get('/album/${existing['id']}') as Map;
        if (check['monitored'] == true) break;
        await Future.delayed(const Duration(seconds: 3));
      }
      await _send('POST', '/command', {'name': 'AlbumSearch', 'albumIds': [existing['id']]});
      return LidarrRequestResult(
        wasMonitored ? LidarrRequestStatus.alreadyMonitored : LidarrRequestStatus.requested,
        albumTitle: title, artistName: artistName, year: year,
      );
    } catch (e) {
      return LidarrRequestResult(LidarrRequestStatus.error, message: e.toString());
    }
  }
}
