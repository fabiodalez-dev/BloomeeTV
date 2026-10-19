import 'dart:async';
import 'dart:io';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/tv/services/tv_catalog_cache.dart';
import 'package:Bloomee/tv/services/tv_diagnostics.dart';
import 'package:Bloomee/tv/services/tv_saved_library.dart';
import 'package:Bloomee/tv/services/tv_workspace.dart';
import 'package:Bloomee/tv/connectors/jellyfin_client.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/tracks.dart';

void main() {
  late Directory root;
  final workspace = TvWorkspace.instance;
  final cache = TvCatalogCache();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bloomee-workspace-');
    await workspace.open(root);
  });
  tearDown(() async {
    await workspace.flush();
    await root.delete(recursive: true);
  });
  test('concurrent mutations are serialized and survive reopening', () async {
    await Future.wait(List.generate(
        20, (_) => workspace.mutate('count', (v) => (v as int? ?? 0) + 1)));
    await workspace.open(root);
    expect(workspace['count'], 20);
  });
  test('source cache falls back offline but authentication failure never does',
      () async {
    await cache.readThrough(
        source: 'jf', key: 'a', load: () async => {'name': 'Album'});
    final result = await cache.readThrough<Map<String, dynamic>>(
        source: 'jf',
        key: 'a',
        load: () async => throw const SocketException('offline'));
    expect(result['name'], 'Album');
    expect(cache.offlineSources['jf'], isNotNull);
    await expectLater(
        cache.readThrough(
            source: 'jf',
            key: 'a',
            load: () async => throw const JellyfinAuthException()),
        throwsA(isA<JellyfinAuthException>()));
  });
  test(
      'cache evicts records and concurrent responses do not overwrite each other',
      () async {
    await Future.wait(List.generate(
        45,
        (i) => cache.readThrough(
            source: 'yt', key: '$i', load: () async => {'i': i})));
    expect((workspace['catalog'] as Map).length, 40);
  });
  test('old profile response cannot populate or disclose new profile cache',
      () async {
    final pending = Completer<Map<String, dynamic>>();
    final request =
        cache.readThrough(source: 'jf', key: 'a', load: () => pending.future);
    final second = Directory('${root.path}/second');
    await workspace.open(second);
    pending.complete({'private': 'old profile'});
    await request;
    expect(workspace['catalog'], isNull);
  });
  test('logout clears cache and rejects a response started before logout',
      () async {
    final pending = Completer<Map<String, dynamic>>();
    final request =
        cache.readThrough(source: 'jf', key: 'a', load: () => pending.future);
    await cache.clearSource('jf');
    pending.complete({'name': 'old'});
    await request;
    expect(workspace['catalog'], isEmpty);
  });
  test('pins and cross-source favorites persist, merge, prefer and split',
      () async {
    final library = TvSavedLibrary(workspace);
    final a = TvReference.item(MediaItem.track(track('a', title: 'Canzone')));
    final b = TvReference.item(MediaItem.track(track('b', title: 'Canzone')));
    await library.togglePin(a);
    await library.togglePin(b);
    await library.movePin(1, -1);
    expect(library.pins.map((r) => r.id), ['b', 'a']);
    await library.addFavorite(a);
    await library.addFavorite(b);
    expect(library.favorites.single['variants'], hasLength(2));
    await library.prefer(a.identity, 'b');
    await library.split(a.identity, 'b');
    expect(library.favorites, hasLength(2));
    await library.merge(
        library.favorites.last['identity'] as String, a.identity);
    expect(library.favorites.single['variants'], hasLength(2));
    await workspace.open(root);
    expect(library.pins.first.id, 'b');
  });
  test('normalization preserves non-Latin characters and version suffixes', () {
    expect(tvNormalize('東京 — LIVE'), '東京 live');
    expect(tvNormalize('宇多田ヒカル'), isNotEmpty);
  });
  test(
      'diagnostic buffer is bounded and redacts bearer tokens, cookies, paths and URLs',
      () {
    final diagnostics = TvDiagnostics();
    for (var i = 0; i < 110; i++) {
      diagnostics.record('HTTP',
          'Authorization: Bearer SECRET\nCookie: SID=PRIVATE; USER=SECRET\nhttps://host/path?ApiKey=TOKEN /Users/fabio/private/file');
    }
    expect(diagnostics.events, hasLength(100));
    expect(diagnostics.export(), isNot(contains('SECRET')));
    expect(diagnostics.export(), isNot(contains('PRIVATE')));
    expect(diagnostics.export(), isNot(contains('TOKEN')));
    expect(diagnostics.export(), isNot(contains('/Users/fabio')));
  });
  test('diagnostics redact quoted secrets and bare network addresses', () {
    final text = TvDiagnostics.redact(
        '{"Authorization":"Bearer PRIVATE TOKEN", "password":"with spaces", "api_key":"SECRET"} 192.168.1.64');
    expect(text, isNot(contains('PRIVATE')));
    expect(text, isNot(contains('SECRET')));
    expect(text, isNot(contains('with spaces')));
    expect(text, isNot(contains('192.168.1.64')));
  });
}
