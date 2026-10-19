import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/tv/connectors/jellyfin_client.dart';
import 'package:Bloomee/tv/connectors/ytmusic_account.dart';
import 'package:Bloomee/tv/services/tv_saved_library.dart';
import 'package:Bloomee/tv/services/tv_search_controller.dart';
import 'package:Bloomee/tv/services/tv_workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/tracks.dart';

void main() {
  TvSearchHit hit(String id, {String title = 'Brano', bool offline = false}) =>
      TvSearchHit(TvReference.item(MediaItem.track(track(id, title: title))),
          id.split('::').first,
          offline: offline);
  test('source errors do not erase successful results', () async {
    final search = TvSearchController();
    addTearDown(search.dispose);
    await search.search('test', {
      'Jellyfin': (_) async => [hit('jf::a')],
      'YouTube': (_) async => throw const SocketException('offline')
    });
    expect(search.hits.single.reference.id, 'jf::a');
    expect(search.errors.keys, ['YouTube']);
    expect(search.loading, isEmpty);
  });
  test(
      'older response, including same-query request, cannot replace new search',
      () async {
    final search = TvSearchController();
    addTearDown(search.dispose);
    final pending = Completer<List<TvSearchHit>>();
    final old = search.search('same', {'old': (_) => pending.future});
    await search.search('same', {
      'new': (_) async => [hit('new::a')]
    });
    pending.complete([hit('old::a')]);
    await old;
    expect(search.hits.single.reference.id, 'new::a');
  });
  test('logout invalidates pending results and empty search clears old items',
      () async {
    final search = TvSearchController();
    addTearDown(search.dispose);
    final pending = Completer<List<TvSearchHit>>();
    final request = search.search('test', {'source': (_) => pending.future});
    search.clear();
    pending.complete([hit('old')]);
    await request;
    expect(search.hits, isEmpty);
    await search.search('', {});
    expect(search.query, isEmpty);
  });
  test('filters offline/version and groups exact variants conservatively',
      () async {
    final search = TvSearchController();
    addTearDown(search.dispose);
    await search.search('test', {
      'all': (_) async => [
            hit('jf::a', title: 'Song'),
            hit('yt::b', title: 'Song'),
            hit('yt::c', title: 'Song Live', offline: true)
          ]
    });
    expect(search.filtered(offlineOnly: true).single.reference.id, 'yt::c');
    expect(search.filtered(version: 'live'), hasLength(1));
    expect(TvSearchController.variants(search.hits).values.map((g) => g.length),
        [2, 1]);
  });
  group('connector pagination', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('bloomee-paging-');
      await TvWorkspace.instance.open(root);
    });
    tearDown(() async {
      await TvWorkspace.instance.flush();
      await root.delete(recursive: true);
    });
    test(
        'Jellyfin loads beyond 400 and sends all selected filters on every page',
        () async {
      var requests = 0;
      final httpClient = MockClient((request) async {
        requests++;
        expect(request.url.queryParameters['Genres'], 'Rock');
        expect(request.url.queryParameters['Years'], '1995');
        expect(request.url.queryParameters['NameStartsWith'], 'A');
        final start = int.parse(request.url.queryParameters['StartIndex']!);
        final limit = int.parse(request.url.queryParameters['Limit']!);
        final end = (start + limit).clamp(0, 550);
        return http.Response(
            jsonEncode({
              'Items': [
                for (var i = start; i < end; i++)
                  {'Id': '$i', 'Name': 'Album $i'}
              ]
            }),
            200);
      });
      addTearDown(httpClient.close);
      final client = JellyfinClient(
          baseUrl: 'http://jf.test',
          userId: 'user',
          token: 'secret',
          client: httpClient);
      final albums =
          await client.albums(genre: 'Rock', year: 1995, startsWith: 'A');
      expect(albums, hasLength(550));
      expect(requests, 6);
    });
    test('Jellyfin stops a server that repeats pages', () async {
      var requests = 0;
      final httpClient = MockClient((_) async {
        requests++;
        return http.Response(
            jsonEncode({
              'Items': [
                {'Id': 'one', 'Name': 'One'}
              ]
            }),
            200);
      });
      addTearDown(httpClient.close);
      final client = JellyfinClient(
          baseUrl: 'http://jf.test', userId: 'user', client: httpClient);
      expect(await client.albums(limit: 1), hasLength(1));
      expect(requests, 2);
    });
    test('health check never reports a cached success while server is offline',
        () async {
      var online = true;
      final transport = MockClient((_) async {
        if (!online) throw const SocketException('offline');
        return http.Response('{"ServerName":"Music"}', 200);
      });
      addTearDown(transport.close);
      final client =
          JellyfinClient(baseUrl: 'http://jf.test', client: transport);
      expect(await client.serverName(), 'Music');
      online = false;
      await expectLater(client.serverName(), throwsA(isA<SocketException>()));
    });
    test('YouTube follows continuation tokens and terminates repeated token',
        () async {
      var requests = 0;
      Map<String, dynamic> song(String id) => {
            'musicResponsiveListItemRenderer': {
              'playlistItemData': {'videoId': id},
              'flexColumns': [
                {
                  'musicResponsiveListItemFlexColumnRenderer': {
                    'text': {
                      'runs': [
                        {'text': 'Song $id'}
                      ]
                    }
                  }
                }
              ]
            }
          };
      final transport = MockClient((request) async {
        requests++;
        final body = jsonDecode(request.body) as Map;
        final id = body.containsKey('continuation') ? 'second' : 'first';
        return http.Response(
            jsonEncode({
              'contents': [song(id)],
              'continuationCommand': {'token': 'repeat'}
            }),
            200);
      });
      addTearDown(transport.close);
      final client = YtMusicClient(client: transport);
      final items = await client.searchType('query', 'song');
      expect(items.map((i) => i.videoId), ['first', 'second']);
      expect(requests, 2);
    });
  });
}
