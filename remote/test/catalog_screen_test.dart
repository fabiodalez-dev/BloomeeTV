import 'dart:async';
import 'package:bloomee_remote/catalog_screen.dart';
import 'package:bloomee_remote/remote_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

class _Remote extends RemoteClient {
  _Remote(this.load)
    : super(
        Uri.parse('http://tv:18794'),
        client: MockClient((_) async => throw StateError('unexpected HTTP')),
      ) {
    capabilities = {'catalog'};
  }
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) load;
  @override
  Future<Map<String, dynamic>> browse(Map<String, dynamic> body) => load(body);
}

void main() {
  testWidgets(
    'search, pagination, play and add to queue operate on result capabilities',
    (tester) async {
      final calls = <Map<String, dynamic>>[],
          commands = <Map<String, dynamic>>[];
      final remote = _Remote((body) async {
        calls.add(body);
        if (body['cursor'] != null) {
          return {
            'items': [
              {
                'id': '0-2',
                'kind': 'song',
                'title': 'Second song',
                'artist': 'Artist',
                'source': 'Jellyfin',
              },
            ],
          };
        }
        return {
          'items': [
            {
              'id': '0-1',
              'kind': 'song',
              'title': 'First song',
              'artist': 'Artist',
              'source': 'YouTube',
            },
          ],
          'next': '0-5',
        };
      });
      addTearDown(remote.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogScreen(
              remote: remote,
              command: (action, [value]) async {
                commands.add({'action': action, 'value': value});
                return true;
              },
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Artist');
      await tester.tap(find.byTooltip('Cerca'));
      await tester.pumpAndSettle();
      expect(calls.single, {
        'kind': 'search',
        'query': 'Artist',
        'filter': 'songs',
        'source': 'all',
      });
      await tester.tap(find.text('First song'));
      await tester.pumpAndSettle();
      expect(commands.last, {'action': 'playItem', 'value': '0-1'});
      await tester.tap(find.byTooltip('Azioni').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aggiungi alla coda'));
      await tester.pumpAndSettle();
      expect(commands.last, {'action': 'enqueueItem', 'value': '0-1'});
      await tester.tap(find.text('Altri risultati'));
      await tester.pumpAndSettle();
      expect(find.text('Second song'), findsOneWidget);
    },
  );
  testWidgets('late search cannot replace the new query', (tester) async {
    final old = Completer<Map<String, dynamic>>();
    final remote = _Remote(
      (body) async => body['query'] == 'old'
          ? old.future
          : {
              'items': [
                {'id': '0-2', 'kind': 'song', 'title': 'New result'},
              ],
            },
    );
    addTearDown(remote.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogScreen(remote: remote, command: (_, [v]) async => true),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'old');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'new');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    old.complete({
      'items': [
        {'id': '0-1', 'kind': 'song', 'title': 'Old result'},
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('New result'), findsOneWidget);
    expect(find.text('Old result'), findsNothing);
  });
  testWidgets('playlist opens tracks and plays all; root list survives back', (
    tester,
  ) async {
    final commands = <String>[];
    final remote = _Remote(
      (body) async => body['kind'] == 'collection'
          ? {
              'title': 'Viaggio',
              'total': 1,
              'editable': true,
              'items': [
                {
                  'id': '0-2',
                  'kind': 'song',
                  'title': 'Playlist song',
                  'owner': '0-1',
                },
              ],
            }
          : {
              'items': [
                {
                  'id': '0-1',
                  'kind': 'playlist',
                  'title': 'Viaggio',
                  'source': 'Locale',
                  'editable': true,
                },
              ],
            },
    );
    addTearDown(remote.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogScreen(
            remote: remote,
            playlists: true,
            command: (a, [v]) async {
              commands.add(a);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Crea playlist'), findsNothing);
    await tester.tap(find.text('Viaggio'));
    await tester.pumpAndSettle();
    expect(find.text('Playlist song'), findsOneWidget);
    await tester.tap(find.byTooltip('Azioni'));
    await tester.pumpAndSettle();
    expect(find.text('Rinomina'), findsNothing);
    expect(find.text('Rimuovi dalla playlist'), findsNothing);
    expect(find.text('Aggiungi a playlist locale'), findsNothing);
    await tester.tap(find.text('Riproduci ora'));
    await tester.pumpAndSettle();
    commands.clear();
    await tester.tap(find.text('Riproduci tutto'));
    await tester.pumpAndSettle();
    expect(commands, ['playItem']);
    await tester.tap(find.byTooltip('Torna all’elenco'));
    await tester.pumpAndSettle();
    expect(find.text('Viaggio'), findsOneWidget);
  });
  testWidgets(
    'search remains usable on a small phone with keyboard and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final remote = _Remote((_) async => {'items': []});
      addTearDown(remote.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewInsets: const EdgeInsets.only(bottom: 260),
                textScaler: TextScaler.linear(1.4),
              ),
              child: Scaffold(
                appBar: AppBar(title: const Text('Cerca')),
                bottomNavigationBar: const SizedBox(height: 80),
                body: CatalogScreen(
                  remote: remote,
                  command: (_, [v]) async => true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomScrollView), findsOneWidget);
    },
  );
  testWidgets('playlist catalog loads only when its tab is opened', (
    tester,
  ) async {
    var calls = 0;
    final remote = _Remote((_) async {
      calls++;
      return {'items': []};
    });
    addTearDown(remote.close);
    Widget screen(bool active) => MaterialApp(
      home: Scaffold(
        body: CatalogScreen(
          key: const ValueKey('library'),
          remote: remote,
          playlists: true,
          active: active,
          command: (_, [v]) async => true,
        ),
      ),
    );
    await tester.pumpWidget(screen(false));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.pumpWidget(screen(true));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets('legacy receiver explains why catalog is unavailable', (
    tester,
  ) async {
    final remote = _Remote((_) async => throw StateError('must not browse'))
      ..capabilities = {};
    addTearDown(remote.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogScreen(remote: remote, command: (_, [v]) async => true),
        ),
      ),
    );
    expect(find.textContaining('Aggiorna Bloomee sulla TV'), findsOneWidget);
  });
}
