import 'dart:async';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/core/models/media_playlist_model.dart';
import 'package:Bloomee/services/bloomee_player.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/db/dao/playlist_dao.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';
import 'package:Bloomee/services/db/global_db.dart';
import 'package:Bloomee/services/db/mappers/media_item_mapper.dart';
import 'package:Bloomee/tv/tv_config.dart';
import 'package:Bloomee/tv/connectors/jellyfin_client.dart';
import 'package:Bloomee/tv/connectors/ytmusic_account.dart';
import 'tv_remote_server.dart';

typedef CatalogPage = Future<Map<String, dynamic>> Function();

class _Entry {
  _Entry(this.title, this.artist, this.kind, this.source, this.tracks,
      {this.localId, this.owner});
  final String title, artist, kind, source;
  final Future<List<Track>> Function() tracks;
  final int? localId;
  final String? owner;
}

/// Capabilities refer to TV-owned objects, never to audio URLs or credentials.
class TvRemoteCatalog {
  TvRemoteCatalog(this.player,
      {PlaylistDAO? playlists,
      TrackDAO? tracks,
      YtMusicClient Function()? youtube,
      JellyfinClient? Function()? jellyfin})
      : _playlists =
            playlists ?? PlaylistDAO(DBProvider.db, TrackDAO(DBProvider.db)),
        _tracks = tracks ?? TrackDAO(DBProvider.db),
        _youtube = youtube ?? (() => TvConfig.youtube),
        _jellyfin = jellyfin ?? (() => TvConfig.jellyfin);
  final BloomeeMusicPlayer player;
  final PlaylistDAO _playlists;
  final TrackDAO _tracks;
  final YtMusicClient Function() _youtube;
  final JellyfinClient? Function() _jellyfin;
  final _entries = <String, _Entry>{};
  final _pages = <String, CatalogPage>{};
  int _epoch = 0, _sequence = 0;
  int _configuration = TvConfig.changes.value;
  void _checkConfiguration() {
    if (_configuration != TvConfig.changes.value) {
      _configuration = TvConfig.changes.value;
      reset();
    }
  }

  void reset() {
    _epoch++;
    _entries.clear();
    _pages.clear();
  }

  void _current(int epoch) {
    _checkConfiguration();
    if (epoch != _epoch) {
      throw const RemoteApiException(
          'Collegamento cambiato. Ripeti la ricerca.');
    }
  }

  String _id() => '$_epoch-${++_sequence}';
  Map<String, dynamic> _register(_Entry e) {
    final id = _id();
    _entries[id] = e;
    if (_entries.length > 6000) _entries.remove(_entries.keys.first);
    return {
      'id': id,
      'title': e.title,
      'artist': e.artist,
      'kind': e.kind,
      'source': e.source,
      'editable': false,
      if (e.owner != null) 'owner': e.owner
    };
  }

  String _page(CatalogPage load) {
    final id = _id();
    Future<Map<String, dynamic>>? pending;
    _pages[id] = () => pending ??= load().catchError((Object e) {
          pending = null;
          throw e;
        });
    if (_pages.length > 100) _pages.remove(_pages.keys.first);
    return id;
  }

  _Entry _entry(String id) =>
      _entries[id] ??
      (throw const RemoteApiException('Risultato scaduto. Aggiorna l’elenco.'));
  Map<String, dynamic> _song(Track t, String source, {String? owner}) =>
      _register(_Entry(t.title, t.artists.map((a) => a.name).join(', '), 'song',
          source, () async => [t],
          owner: owner));
  Map<String, dynamic> _yt(YtItem item) {
    if (item.kind == 'song') return _song(item.toTrack(), 'YouTube');
    return _register(_Entry(
        item.title,
        item.subtitle,
        'playlist',
        'YouTube',
        () async => (await _youtube().collection(item.browseId!))
            .tracks
            .map((t) => t.toTrack())
            .toList()));
  }

  Map<String, dynamic> _jf(JfItem item, JellyfinClient client) {
    if (item.type == 'Audio') return _song(item.toTrack(client), 'Jellyfin');
    return _register(_Entry(
        item.name,
        'Playlist Jellyfin',
        'playlist',
        'Jellyfin',
        () async => (await client.playlistTracks(item.id))
            .map((t) => t.toTrack(client))
            .toList()));
  }

  Map<String, dynamic> _local(PlaylistDB p) => _register(_Entry(
      p.name,
      'Playlist locale',
      'playlist',
      'Locale',
      () async => (await _playlists.getPlaylistTracks(p.id))
          .map(trackDBToTrack)
          .toList(),
      localId: p.id));

  Future<Map<String, dynamic>> browse(Map<String, dynamic> body) async {
    _checkConfiguration();
    validateRemoteBrowse(body);
    if (body['cursor'] != null) {
      final load = _pages[body['cursor']];
      if (load == null) {
        throw const RemoteApiException('Pagina scaduta. Aggiorna l’elenco.');
      }
      return load();
    }
    switch (body['kind']) {
      case 'collection':
        return _collection(body['id'] as String, 0);
      case 'playlists':
        return _search('', 'playlists', body['source'] as String? ?? 'all', {},
            library: true);
      case 'search':
        return _search(
            (body['query'] as String).trim(),
            body['filter'] as String? ?? 'songs',
            body['source'] as String? ?? 'all', {});
      default:
        throw const FormatException();
    }
  }

  Future<Map<String, dynamic>> _collection(String id, int start,
      {List<Track>? cached}) async {
    final epoch = _epoch, entry = _entry(id);
    final tracks =
        cached ?? await entry.tracks().timeout(const Duration(seconds: 35));
    _current(epoch);
    final rows = tracks
        .skip(start)
        .take(50)
        .map((t) =>
            _song(t, entry.source, owner: entry.localId == null ? null : id))
        .toList();
    return {
      'items': rows,
      'title': entry.title,
      'total': tracks.length,
      'editable': false,
      'next': start + 50 < tracks.length
          ? _page(() => _collection(id, start + 50, cached: tracks))
          : null,
      'errors': <String>[]
    };
  }

  Future<Map<String, dynamic>> _search(
      String query, String filter, String source, Map<String, dynamic> cursor,
      {bool library = false}) async {
    final epoch = _epoch;
    final rows = <Map<String, dynamic>>[],
        errors = <String>[],
        next = <String, dynamic>{};
    final initial = cursor.isEmpty;
    final jobs = <Future<void>>[];
    void run(String key, Future<void> Function(bool Function()) load) {
      if (!initial && !cursor.containsKey(key)) return;
      jobs.add(() async {
        var accepted = true;
        try {
          await load(() => accepted && epoch == _epoch)
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          errors.add('$key non disponibile. Riprova.');
        } finally {
          accepted = false;
        }
      }());
    }

    if (source == 'all' || source == 'local') {
      run('Locale', (accepted) async {
        if (filter == 'songs' && !library) {
          final start = cursor['Locale'] as int? ?? 0;
          final items =
              await _tracks.searchTracks(query, limit: 30, offset: start);
          if (!accepted()) return;
          rows.addAll(items.map((t) => _song(trackDBToTrack(t), 'Locale')));
          if (items.length == 30) next['Locale'] = start + items.length;
        } else {
          final items =
              await _playlists.getPlaylistsByType(PlaylistTypeDB.userPlaylist);
          if (!accepted()) return;
          final matches = items
              .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
              .toList();
          final start = cursor['Locale'] as int? ?? 0;
          rows.addAll(matches.skip(start).take(30).map(_local));
          if (start + 30 < matches.length) next['Locale'] = start + 30;
        }
      });
    }
    if (source == 'all' || source == 'youtube') {
      run('YouTube', (accepted) async {
        final yt = _youtube();
        if (library) {
          if (!yt.loggedIn) return;
          final items = await yt.libraryPlaylists();
          if (!accepted()) return;
          final matches = items.where((t) => t.browseId != null).toList();
          final start = cursor['YouTube'] as int? ?? 0;
          rows.addAll(matches.skip(start).take(30).map(_yt));
          if (start + 30 < matches.length) next['YouTube'] = start + 30;
        } else {
          final page = await yt.searchPage(query,
              kind: filter == 'playlists' ? 'playlist' : 'song',
              continuation: cursor['YouTube'] as String?);
          if (!accepted()) return;
          rows.addAll(page.items
              .where((t) => filter == 'playlists'
                  ? t.browseId != null && t.kind == 'playlist'
                  : t.videoId != null)
              .map(_yt));
          if (page.next != null && page.next != cursor['YouTube']) {
            next['YouTube'] = page.next;
          }
        }
      });
    }
    final jf = _jellyfin();
    if (jf != null && (source == 'all' || source == 'jellyfin')) {
      run('Jellyfin', (accepted) async {
        final start = cursor['Jellyfin'] as int? ?? 0;
        final items = await jf.search(query,
            types: filter == 'playlists' ? 'Playlist' : 'Audio',
            limit: 30,
            start: start);
        if (!accepted()) return;
        rows.addAll(items.map((t) => _jf(t, jf)));
        if (items.length == 30) next['Jellyfin'] = start + items.length;
      });
    }
    await Future.wait(jobs);
    _current(epoch);
    return {
      'items': rows,
      'errors': errors,
      'next': next.isEmpty
          ? null
          : _page(() => _search(query, filter, source, next, library: library))
    };
  }

  Future<void> command(Map<String, dynamic> body) async {
    _checkConfiguration();
    final epoch = _epoch, action = body['action'], value = body['value'];
    if (!['playItem', 'enqueueItem', 'shuffleItem'].contains(action))
      throw const FormatException();
    final entry = _entry(value as String),
        tracks = await entry.tracks().timeout(const Duration(seconds: 35));
    _current(epoch);
    if (tracks.isEmpty) {
      throw const RemoteApiException(
          'Questa playlist non contiene brani riproducibili.');
    }
    if (action == 'enqueueItem') {
      await player.addQueueTracks(tracks, atLast: true);
    } else {
      await player.loadPlaylist(Playlist(tracks: tracks, title: entry.title),
          doPlay: true, shuffling: action == 'shuffleItem');
    }
  }
}
