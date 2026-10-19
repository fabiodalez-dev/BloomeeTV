import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/tv/connectors/jellyfin_client.dart';
import 'package:Bloomee/tv/connectors/ytmusic_account.dart';
import 'package:Bloomee/tv/screens/tv_search_screen.dart';
import 'package:Bloomee/tv/tv_focus.dart';
import 'package:Bloomee/tv/ui/tv_widgets.dart';
import 'package:Bloomee/tv/services/tv_saved_library.dart';
import 'package:Bloomee/tv/services/tv_search_controller.dart';
import 'package:Bloomee/tv/services/tv_workspace.dart';
import 'package:Bloomee/tv/services/tv_catalog_cache.dart';
import 'package:Bloomee/plugins/blocs/plugin/plugin_bloc.dart';
import 'package:Bloomee/plugins/blocs/plugin/plugin_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/tracks.dart';

class _PluginStub extends Fake implements PluginBloc {
  @override
  Stream<PluginState> get stream => const Stream.empty();
  @override
  PluginState get state => const PluginState.initial();
}

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tv-search-performance-');
    await TvWorkspace.instance.open(root);
  });
  tearDown(() async {
    await TvWorkspace.instance.flush();
    await root.delete(recursive: true);
  });
  TvSearchHit hit(String id) =>
      TvSearchHit(TvReference.item(MediaItem.track(track(id))), 'test');
  test('albums are deferred until first songs and do not gate them', () async {
    final search = TvSearchController();
    addTearDown(search.dispose);
    final songs = Completer<List<TvSearchHit>>();
    final albums = Completer<List<TvSearchHit>>();
    var startedAlbums = false;
    final request = search.search('artist', {
      'songs': (_) => songs.future
    }, deferred: {
      'albums': (_) {
        startedAlbums = true;
        return albums.future;
      }
    });
    await Future<void>.delayed(Duration.zero);
    expect(startedAlbums, isFalse);
    songs.complete([hit('song')]);
    await Future<void>.delayed(Duration.zero);
    expect(search.hits.single.reference.id, 'song');
    expect(startedAlbums, isTrue);
    albums.complete([hit('album')]);
    await request;
    expect(search.hits.map((h) => h.reference.id), ['song', 'album']);
  });
  test('a slow song provider cannot prevent albums from starting', () async {
    final search =
        TvSearchController(timeout: const Duration(milliseconds: 80));
    addTearDown(search.dispose);
    final pending = Completer<List<TvSearchHit>>();
    final request = search.search('artist', {'songs': (_) => pending.future},
        deferred: {
          'albums': (_) async => [hit('album')]
        },
        secondaryDelay: const Duration(milliseconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(search.hits.single.reference.id, 'album');
    pending.complete([]);
    await request;
  });
  test(
      'search response cache is in memory and invalidates on logout and profile change',
      () async {
    final cache = TvCatalogCache();
    var calls = 0;
    Future<Map<String, dynamic>> load() async => {'call': ++calls};
    await cache.search(source: 'youtube', key: 'q', load: load);
    await cache.search(source: 'youtube', key: 'q', load: load);
    expect(calls, 1);
    expect(TvWorkspace.instance['catalog'], isNull);
    expect(await File('${root.path}/tv-catalog.json').exists(), isFalse);
    await cache.clearSource('youtube');
    await cache.search(source: 'youtube', key: 'q', load: load);
    expect(calls, 2);
    await TvWorkspace.instance.open(Directory('${root.path}/other'));
    await cache.search(source: 'youtube', key: 'q', load: load);
    expect(calls, 3);
  });
  test('legacy large catalog migrates once without bloating later preferences',
      () async {
    await File('${root.path}/tv-workspace.json').writeAsString(jsonEncode({
      'catalog': {'large': 'x' * 600000},
      'onboardedTv': true
    }));
    await TvWorkspace.instance.open(root);
    await TvWorkspace.instance.set('searchFilters', {'source': 'Tutte'});
    expect(
        await File('${root.path}/tv-workspace.json').length(), lessThan(1000));
    final catalogFile = File('${root.path}/tv-catalog.json');
    final before = await catalogFile.readAsString();
    await TvWorkspace.instance.set('otherPreference', 2);
    expect(await catalogFile.readAsString(), before);
    await TvWorkspace.instance.open(root);
    expect(
        (TvWorkspace.instance['catalog'] as Map)['large'], hasLength(600000));
    expect(TvWorkspace.instance['onboardedTv'], isTrue);
  });
  test('reference decoding is reused when rendering several metadata fields',
      () {
    final reference =
        TvReference.item(MediaItem.track(track('cached', title: 'Title')));
    expect(identical(reference.item, reference.item), isTrue);
    final restored = TvReference(Map<String, dynamic>.from(reference.payload));
    expect(identical(restored.item, restored.item), isTrue);
    expect(restored.title, 'Title');
    expect(restored.id, 'cached');
  });
  testWidgets(
      'first song title is visible without scrolling or waiting for albums',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final search = TvSearchController();
    addTearDown(search.dispose);
    await search.search('test', {
      'songs': (_) async =>
          [hit('first'), for (var i = 0; i < 20; i++) hit('other-$i')]
    });
    await tester.pumpWidget(BlocProvider<PluginBloc>.value(
        value: _PluginStub(),
        child: MaterialApp(home: TvSearchScreen(controller: search))));
    await tester.pumpAndSettle();
    final title = find.text('Brano first');
    expect(title.hitTestable(), findsOneWidget);
    expect(tester.getRect(title).bottom, lessThan(450));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('Tutti i 21 brani'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('filters are collapsed so the first result row fits on the TV',
      (tester) async {
    await tester.pumpWidget(BlocProvider<PluginBloc>.value(
        value: _PluginStub(),
        child: const MaterialApp(home: TvSearchScreen())));
    expect(find.text('Solo scaricati'), findsNothing);
    await tester.tap(find.text('Filtri · Tutte'));
    await tester.pumpAndSettle();
    expect(find.text('Solo scaricati'), findsOneWidget);
    expect(find.text('Jellyfin'), findsNothing);
    await tester.tap(find.text('Filtri · Tutte'));
    await tester.pumpAndSettle();
    expect(find.text('Solo scaricati'), findsNothing);
  });
  testWidgets('search categories stay visible and aligned below the input',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(BlocProvider<PluginBloc>.value(
        value: _PluginStub(),
        child: const MaterialApp(home: TvSearchScreen())));
    await tester.pumpAndSettle();
    final voice = tester.getRect(find.widgetWithText(TvPillButton, 'Parla'));
    final categories = ['Tutto', 'Brani', 'Album', 'Artisti'];
    Rect? previous;
    for (final kind in categories) {
      final button = find.byKey(ValueKey('search-kind-$kind'));
      expect(button.hitTestable(), findsOneWidget);
      final rect = tester.getRect(button);
      expect(rect.top, greaterThan(voice.bottom));
      if (previous != null) {
        expect(rect.top, closeTo(previous.top, .1));
        expect(rect.left - previous.right, closeTo(12, .1));
      } else {
        expect(rect.left, closeTo(voice.left, .1));
      }
      previous = rect;
    }
    expect(
        tester
            .getRect(
                find.text('Premi Parla oppure OK sulla barra per scrivere.'))
            .left,
        closeTo(voice.left, .1));
    expect(find.text('Solo scaricati'), findsNothing);
    await tester.tap(find.text('Filtri · Tutte'));
    await tester.pumpAndSettle();
    for (final kind in categories) {
      expect(find.byKey(ValueKey('search-kind-$kind')).hitTestable(),
          findsOneWidget);
    }
    expect(find.text('Solo scaricati'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('voice has initial focus and is the TV shell entry target',
      (tester) async {
    final scope = FocusScopeNode();
    addTearDown(scope.dispose);
    await tester.pumpWidget(BlocProvider<PluginBloc>.value(
        value: _PluginStub(),
        child: MaterialApp(
            home: FocusScope(node: scope, child: const TvSearchScreen()))));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-search-voice');
    final filter = tester.widget<TvPillButton>(
        find.widgetWithText(TvPillButton, 'Filtri · Tutte'));
    expect(filter.autofocus, isFalse);
    expect(tvFocusFirstIn(scope), isTrue);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-search-voice');
  });
  testWidgets('artist category displays artist results without song rows',
      (tester) async {
    final search = TvSearchController();
    addTearDown(search.dispose);
    await tester.pumpWidget(BlocProvider<PluginBloc>.value(
        value: _PluginStub(),
        child: MaterialApp(home: TvSearchScreen(controller: search))));
    await tester.tap(find.byKey(const ValueKey('search-kind-Artisti')));
    await tester.pumpAndSettle();
    // Feed a mixed provider response to exercise the screen's actual kind filter.
    await search.search('artist', {
      'test': (_) async => [
            hit('song'),
            TvSearchHit(
                TvReference.item(const MediaItem.artist(ArtistSummary(
                    id: 'artist-result', name: 'Artista trovato'))),
                'test')
          ]
    });
    await tester.pumpAndSettle();
    expect(find.text('Artista trovato').hitTestable(), findsOneWidget);
    expect(find.text('Brano song'), findsNothing);
    expect(
        tester
            .widget<TvPillButton>(
                find.byKey(const ValueKey('search-kind-Artisti')))
            .primary,
        isTrue);
    expect(tester.takeException(), isNull);
  });
  test('YouTube never promotes play counts or durations to artist names',
      () async {
    final transport = MockClient((_) async => http.Response(
        jsonEncode({
          'contents': [
            {
              'musicResponsiveListItemRenderer': {
                'playlistItemData': {'videoId': 'track'},
                'flexColumns': [
                  {
                    'musicResponsiveListItemFlexColumnRenderer': {
                      'text': {
                        'runs': [
                          {'text': 'Song'}
                        ]
                      }
                    }
                  },
                  {
                    'musicResponsiveListItemFlexColumnRenderer': {
                      'text': {
                        'runs': [
                          {'text': '8,6K riproduzioni • Real Artist • 3:12'}
                        ]
                      }
                    }
                  }
                ]
              }
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    addTearDown(transport.close);
    final page = await YtMusicClient(client: transport).searchPage('stats');
    expect(page.items.single.artists.single.name, 'Real Artist');
    expect(page.items.single.duration, const Duration(minutes: 3, seconds: 12));
  });
  test('a stalled provider cannot hold successful results for minutes',
      () async {
    final search =
        TvSearchController(timeout: const Duration(milliseconds: 30));
    addTearDown(search.dispose);
    final stalled = Completer<List<TvSearchHit>>();
    final request = search.search('artist', {
      'fast': (_) async => [hit('fast')],
      'slow': (_) => stalled.future,
    });
    await Future<void>.delayed(Duration.zero);
    expect(search.hits.single.reference.id, 'fast');
    expect(search.loading, {'slow'});
    await request;
    expect(search.loading, isEmpty);
    expect(search.errors['slow'], contains('non ha risposto in tempo'));
    stalled.complete([hit('late')]);
    await Future<void>.delayed(Duration.zero);
    expect(search.hits.single.reference.id, 'fast');
  });
  test('explicit next page appends without duplicates and ignores stale pages',
      () async {
    final search = TvSearchController();
    addTearDown(search.dispose);
    await search.search('one', {
      'test': (_) async => [hit('a')]
    });
    await search.loadMore('test', (_) async => [hit('a'), hit('b')]);
    expect(search.hits.map((h) => h.reference.id), ['a', 'b']);
    final pending = Completer<List<TvSearchHit>>();
    final more = search.loadMore('test', (_) => pending.future);
    await search.search('two', {
      'new': (_) async => [hit('new')]
    });
    pending.complete([hit('stale')]);
    await more;
    expect(search.hits.single.reference.id, 'new');
  });
  test('unconfigured sources are absent from selectable search filters', () {
    expect(TvSearchController.sources(jellyfin: false, plugin: false),
        ['Tutte', 'Locale', 'YouTube']);
    expect(TvSearchController.sources(jellyfin: true, plugin: true),
        containsAll(['Jellyfin', 'Plugin']));
  });
  test(
      'guide is offered once across app restarts, and skipped for configured TV',
      () async {
    final root = await Directory.systemTemp.createTemp('tv-guide-once-');
    addTearDown(() async {
      await TvWorkspace.instance.flush();
      await root.delete(recursive: true);
    });
    await TvWorkspace.instance.open(root);
    expect(
        await TvWorkspace.instance.claimGuidePrompt(configured: false), isTrue);
    await TvWorkspace.instance.open(root);
    expect(await TvWorkspace.instance.claimGuidePrompt(configured: false),
        isFalse);
    await TvWorkspace.instance.set('introShownTv', false);
    expect(
        await TvWorkspace.instance.claimGuidePrompt(configured: true), isFalse);
    expect(await TvWorkspace.instance.claimGuidePrompt(configured: false),
        isFalse);
  });
  test('Jellyfin search returns its first page without traversing the catalog',
      () async {
    var requests = 0;
    final transport = MockClient((request) async {
      requests++;
      expect(request.url.queryParameters['StartIndex'], '0');
      expect(request.url.queryParameters['Limit'], '60');
      return http.Response(
          jsonEncode({
            'Items': [
              for (var i = 0; i < 60; i++) {'Id': '$i', 'Name': 'Artist $i'}
            ]
          }),
          200);
    });
    addTearDown(transport.close);
    final client = JellyfinClient(
        baseUrl: 'http://jf.test', userId: 'user', client: transport);
    expect(await client.search('artist'), hasLength(60));
    expect(requests, 1);
  });
  test('YouTube returns a continuation without fetching it until requested',
      () async {
    var requests = 0;
    final transport = MockClient((request) async {
      requests++;
      final body = jsonDecode(request.body) as Map;
      if (requests == 1) {
        expect(body['query'], 'artist');
        expect(body['params'], YtMusicClient.searchParams['artist']);
      } else {
        expect(body['continuation'], 'next');
        expect(body.containsKey('query'), isFalse);
      }
      return http.Response(
          jsonEncode({
            'contents': [],
            if (requests == 1) 'continuationCommand': {'token': 'next'}
          }),
          200);
    });
    addTearDown(transport.close);
    final client = YtMusicClient(client: transport);
    final page = await client.searchPage('artist', kind: 'artist');
    expect(requests, 1);
    expect(page.next, 'next');
    final second = await client.searchPage('artist',
        kind: 'artist', continuation: page.next);
    expect(requests, 2);
    expect(second.next, isNull);
  });
  testWidgets(
      'remote Cancel dismisses voice input without submitting partial words',
      (tester) async {
    const channel = MethodChannel('bloomee_tv/voice');
    final listening = Completer<String?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listen') return listening.future;
      if (call.method == 'cancel' && !listening.isCompleted)
        listening.complete(null);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    String? result = 'not completed';
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await listenVoice(context);
                    },
                    child: const Text('Voice'))))));
    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
                const MethodCall('partial', 'Artist partial')),
            (_) {});
    await tester.pump();
    expect(find.text('Artist partial'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Annulla'), findsNothing);
    expect(result, isNull);
  });
}
