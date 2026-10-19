import 'dart:io';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/db/dao/cache_dao.dart';
import 'package:Bloomee/services/db/dao/download_dao.dart';
import 'package:Bloomee/services/db/dao/playlist_dao.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';
import 'package:Bloomee/services/db/mappers/media_item_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tracks.dart';

void main() {
  late Directory root;
  late TrackDAO tracks;
  late PlaylistDAO playlists;
  late SettingsDAO settings;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bloomee-regression-');
    await DBProvider.init(
        appSupportPath: root.path, appDocumentsPath: root.path);
    tracks = TrackDAO(DBProvider.db);
    playlists = PlaylistDAO(DBProvider.db, tracks);
    settings = SettingsDAO(DBProvider.db);
  });
  tearDown(() async {
    final db = await DBProvider.db;
    if (db.isOpen) await db.close();
    await root.delete(recursive: true);
  });
  test('playlist create, rename, cover, ordered edit and delete persist',
      () async {
    final id = (await playlists.createPlaylist('Test'))!;
    final songs = [track('a'), track('b'), track('c')];
    await playlists.setPlaylistTracks(id, songs);
    await playlists.setPlaylistTracks(id, [songs[2], songs[0]]);
    await playlists.updatePlaylistMeta(id, name: 'Rinominata');
    await playlists.updatePlaylistThumbnail(
        id, 'https://example.test/cover.jpg');
    final read =
        (await playlists.getPlaylistTracks(id)).map(trackDBToTrack).toList();
    expect(read.map((t) => t.id), ['c', 'a']);
    expect((await playlists.getPlaylistById(id))!.name, 'Rinominata');
    expect((await playlists.getPlaylistById(id))!.thumbnail!.url,
        'https://example.test/cover.jpg');
    await playlists.deletePlaylist(id);
    expect(await playlists.getPlaylistById(id), isNull);
  });
  test('download entry distinguishes an available file from a missing file',
      () async {
    final downloads = DownloadDAO(DBProvider.db, tracks, playlists);
    final file = await File('${root.path}/a.audio').writeAsBytes([1, 2, 3]);
    await downloads.putDownload(
        fileName: 'a.audio', filePath: root.path, track: track('a'));
    expect((await downloads.getValidDownloads()).map((d) => d.mediaId), ['a']);
    await file.delete();
    expect(await downloads.getValidDownloads(), isEmpty);
  });
  test('settings and queue order survive closing and reopening the database',
      () async {
    await settings.putSettings({'one': 'uno', 'two': 'due'});
    await settings.putSettingBool('enabled', true);
    await (await DBProvider.db).close();
    await DBProvider.init(
        appSupportPath: root.path, appDocumentsPath: root.path);
    expect(await settings.getSettingStr('two'), 'due');
    expect(await settings.getSettingBool('enabled'), isTrue);
    await settings.removeSettingStr('one');
    expect(await settings.getSettingStr('one'), isNull);
  });
  test('local search pages are bounded and disjoint', () async {
    await tracks.upsertTracks([
      for (var i = 0; i < 75; i++) track('page-$i', title: 'Paging song $i')
    ]);
    final first = await tracks.searchTracks('Paging', limit: 60);
    final second = await tracks.searchTracks('Paging', limit: 60, offset: 60);
    expect(first, hasLength(60));
    expect(second, hasLength(15));
    expect(
        first
            .map((t) => t.mediaId)
            .toSet()
            .intersection(second.map((t) => t.mediaId).toSet()),
        isEmpty);
    expect(await tracks.searchTracks('Paging', offset: 100), isEmpty);
  });
  test('search matches artists and preserves non-Latin names', () async {
    await tracks.upsertTracks([
      track('a', title: 'Una canzone', artist: '宇多田ヒカル'),
      track('b', artist: 'Altro')
    ]);
    expect((await tracks.searchTracks('宇多田', limit: 0)).map((t) => t.mediaId),
        ['a']);
  });
  test('a retired DAO cannot read or write another profile database', () async {
    await settings.putSettingStr('profile', 'original');
    await DBProvider.switchDirectory('${root.path}/other-profile');
    final next = SettingsDAO(DBProvider.db);
    await next.putSettingStr('profile', 'other');
    await expectLater(
        settings.putSettingStr('profile', 'leaked'), throwsA(anything));
    expect(await next.getSettingStr('profile'), 'other');
    await DBProvider.switchDirectory(root.path);
    expect(
        await SettingsDAO(DBProvider.db).getSettingStr('profile'), 'original');
  });
  test('cache roundtrip and expired entries are purged', () async {
    final cache = CacheDAO(DBProvider.db);
    await cache.putCache('valid', '{"ok":true}', ttl: const Duration(hours: 1));
    await cache.putCache('expired', 'old', ttl: const Duration(seconds: -1));
    expect(await cache.getCacheValue('valid'), '{"ok":true}');
    expect(await cache.getCacheValue('expired'), isNull);
  });
}
