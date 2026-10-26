import 'package:Bloomee/tv/tv_config.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/core/models/media_playlist_model.dart';
import 'package:Bloomee/services/bloomee_player.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/db/dao/playlist_dao.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';
import 'package:Bloomee/tv/connectors/jellyfin_client.dart';
import 'package:Bloomee/tv/connectors/ytmusic_account.dart';
import 'package:Bloomee/tv/services/tv_remote_catalog.dart';
import 'package:Bloomee/tv/services/tv_remote_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/tracks.dart';

class _Player implements BloomeeMusicPlayer {
  final tracks = <Track>[];
  Playlist? loaded;
  bool shuffled = false;
  @override
  List<Track> get queueTracks => List.from(tracks);
  @override
  Future<void> loadPlaylist(Playlist playlist,
      {int idx = 0, bool doPlay = false, bool shuffling = false}) async {
    loaded = playlist;
    shuffled = shuffling;
  }

  @override
  Future<void> addQueueTracks(List<Track> items, {bool atLast = false}) async {
    tracks.addAll(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _YouTube extends YtMusicClient {
  @override
  bool get loggedIn => false;
  @override
  Future<YtSearchPage> searchPage(String query,
          {String? kind, String? continuation}) async =>
      YtSearchPage([
        YtItem(
            kind: 'song',
            title: 'YouTube Song',
            videoId: 'abcdefghijk',
            artists: [const YtRef('Artist', null)])
      ], null);
}

void main() {
  late Directory root;
  late PlaylistDAO playlists;
  late TrackDAO tracks;
  late _Player player;
  late TvRemoteCatalog catalog;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('remote-catalog-');
    await DBProvider.init(
        appSupportPath: root.path,
        appDocumentsPath: root.path,
        allowLegacyRecovery: false);
    tracks = TrackDAO(DBProvider.db);
    playlists = PlaylistDAO(DBProvider.db, tracks);
    player = _Player();
    catalog = TvRemoteCatalog(player,
        playlists: playlists,
        tracks: tracks,
        youtube: () => _YouTube(),
        jellyfin: () => null);
  });
  tearDown(() async {
    catalog.reset();
    final db = await DBProvider.db;
    if (db.isOpen) await db.close();
    await root.delete(recursive: true);
  });
  test('search exposes display metadata, plays and queues a TV-owned result',
      () async {
    final page = await catalog
        .browse({'kind': 'search', 'query': 'artist', 'source': 'youtube'});
    final item = (page['items'] as List).single as Map;
    expect(item['title'], 'YouTube Song');
    expect(item.keys.toSet(),
        {'id', 'title', 'artist', 'kind', 'source', 'editable'});
    await catalog.command({'action': 'playItem', 'value': item['id']});
    expect(player.loaded!.tracks.single.title, 'YouTube Song');
    await catalog.command({'action': 'enqueueItem', 'value': item['id']});
    expect(player.tracks, hasLength(1));
    catalog.reset();
    await expectLater(
        catalog.command({'action': 'playItem', 'value': item['id']}),
        throwsA(isA<RemoteApiException>()));
  });
  test('existing local playlist opens and plays without modifying its contents',
      () async {
    final dbId = (await playlists.createPlaylist('Viaggio'))!;
    await playlists
        .addTracksToPlaylist(dbId, [track('plugin::a'), track('plugin::b')]);
    final library =
        await catalog.browse({'kind': 'playlists', 'source': 'local'});
    final playlist = (library['items'] as List).single as Map;
    expect(playlist['editable'], false);
    final contents =
        await catalog.browse({'kind': 'collection', 'id': playlist['id']});
    expect(contents['total'], 2);
    expect(contents['editable'], false);
    await catalog.command({'action': 'playItem', 'value': playlist['id']});
    expect(player.loaded!.tracks.map((t) => t.id), ['plugin::a', 'plugin::b']);
    await catalog.command({'action': 'shuffleItem', 'value': playlist['id']});
    expect(player.shuffled, true);
    await catalog.command({'action': 'enqueueItem', 'value': playlist['id']});
    expect(player.tracks, hasLength(2));
    expect(await playlists.getPlaylistTrackCount(dbId), 2);
    expect((await playlists.getPlaylistById(dbId))!.name, 'Viaggio');
    await expectLater(
        catalog.command({'action': 'createPlaylist', 'value': 'Nuova'}),
        throwsFormatException);
    for (final action in [
      'createPlaylist',
      'saveQueue',
      'playlistAdd',
      'playlistRemove',
      'playlistRename'
    ]) {
      expect(
          () => validateRemoteCommand({
                'action': action,
                'value': {'playlist': playlist['id'], 'item': '0-1'}
              }),
          throwsFormatException);
    }
  });
  test('playlist pagination is stable on retry and reset revokes cursors',
      () async {
    for (var i = 0; i < 31; i++) {
      await playlists.createPlaylist('Lista $i');
    }
    final first =
        await catalog.browse({'kind': 'playlists', 'source': 'local'});
    expect(first['items'], hasLength(30));
    expect(first['next'], isNotNull);
    final next = await catalog.browse({'cursor': first['next']});
    expect(next['items'], hasLength(1));
    expect(await catalog.browse({'cursor': first['next']}), same(next));
    catalog.reset();
    await expectLater(catalog.browse({'cursor': first['next']}),
        throwsA(isA<RemoteApiException>()));
  });
  test(
      'Jellyfin playlist preserves playlist order across pages without leaking tokens',
      () async {
    final calls = <int>[];
    final client = JellyfinClient(
        baseUrl: 'http://jf.test',
        token: 'SECRET',
        userId: 'user',
        client: MockClient((r) async {
          expect(r.url.path, '/Playlists/list/Items');
          expect(r.url.queryParameters.containsValue('SECRET'), isFalse);
          final start = int.parse(r.url.queryParameters['StartIndex']!);
          calls.add(start);
          return http.Response(
              jsonEncode({
                'TotalRecordCount': 101,
                'Items': List.generate(
                    start == 0 ? 100 : 1,
                    (i) => {
                          'Id': '${start + i}',
                          'Name': 'Song ${start + i}',
                          'Type': 'Audio'
                        })
              }),
              200);
        }));
    final items = await client.playlistTracks('list');
    expect(items, hasLength(101));
    expect(items.last.name, 'Song 100');
    expect(calls, [0, 100]);
  });
  test('account changes revoke old catalog capabilities before they can play',
      () async {
    final result = await catalog
        .browse({'kind': 'search', 'query': 'song', 'source': 'youtube'});
    final id = (result['items'] as List).single['id'];
    TvConfig.changes.value++;
    await expectLater(catalog.command({'action': 'playItem', 'value': id}),
        throwsA(isA<RemoteApiException>()));
    expect(player.loaded, isNull);
    expect(
        (await catalog.browse(
            {'kind': 'search', 'query': 'song', 'source': 'youtube'}))['items'],
        isNotEmpty);
  });
  test('new protocol rejects URLs, invalid capabilities and oversized names',
      () {
    for (final body in [
      {'kind': 'collection', 'id': 'http://evil'},
      {'kind': 'search', 'query': ''},
      {'cursor': '1-2', 'kind': 'search'},
      {'kind': 'search', 'query': 'x', 'source': 'shell'}
    ]) {
      expect(() => validateRemoteBrowse(body), throwsFormatException);
    }
    expect(
        () => validateRemoteCommand(
            {'action': 'playItem', 'value': 'http://evil'}),
        throwsFormatException);
    expect(
        () => validateRemoteCommand({
              'action': 'playlistAdd',
              'value': {'playlist': '1-2', 'item': '1-3', 'token': 'secret'}
            }),
        throwsFormatException);
  });
}
