import 'dart:io';
import 'package:Bloomee/tv/services/tv_artwork_server.dart';
import 'package:Bloomee/tv/services/tv_downloads.dart';
import 'package:Bloomee/tv/services/tv_operations.dart';
import 'package:Bloomee/tv/services/tv_storage.dart';
import 'package:Bloomee/tv/services/tv_workspace.dart';
import 'package:Bloomee/services/player/media_resolver_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/tracks.dart';

class RealNetwork extends HttpOverrides {}

void main() {
  test(
      'artwork proxy hides credentials, revokes prior URL and serves only artwork',
      () async {
    final server = TvArtworkServer(
        clientFactory: () => MockClient((request) async {
              expect(request.headers['authorization'], 'secret');
              return http.Response.bytes([1, 2, 3], 200,
                  headers: {'content-type': 'image/png'});
            }));
    await HttpOverrides.runWithHttpOverrides(() async {
      final client = http.Client();
      try {
        final first = (await server.publish(Uri.parse('https://jf.test/image'),
            headers: {'Authorization': 'secret'},
            bind: InternetAddress.loopbackIPv4,
            advertisedHost: '127.0.0.1'))!;
        expect(first.toString(), isNot(contains('secret')));
        expect((await client.get(first)).bodyBytes, [1, 2, 3]);
        final second = (await server.publish(Uri.parse('https://jf.test/other'),
            headers: {'Authorization': 'secret'},
            bind: InternetAddress.loopbackIPv4,
            advertisedHost: '127.0.0.1'))!;
        expect((await client.get(first)).statusCode, 404);
        expect((await client.get(second)).statusCode, 200);
        expect((await client.get(second.replace(path: '/'))).statusCode, 404);
      } finally {
        client.close();
        await server.close();
      }
    }, RealNetwork());
  });
  group('TV transfer quota and operation state', () {
    late Directory root;
    late Future<int> Function(String) oldSpace;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('bloomee-downloads-');
      await TvWorkspace.instance.open(root);
      oldSpace = TvStorage.freeBytes;
      TvStorage.freeBytes = (_) async => 1024 * 1024 * 1024;
    });
    tearDown(() async {
      await TvOperations.instance.cancelAll();
      TvStorage.freeBytes = oldSpace;
      await root.delete(recursive: true);
    });
    test('file is registered only after a complete quota-checked transfer',
        () async {
      String? registered;
      expect(
          await TvDownloads.save(track('song'),
              directory: () async => root,
              register: (track, path) async {
                registered = path;
                expect(await File(path).readAsBytes(), [1, 2, 3]);
              },
              resolve: (_) async => ResolvedMediaSource(
                  uri: Uri.parse('https://example.test/audio'),
                  isOffline: false),
              clientFactory: () =>
                  MockClient((_) async => http.Response.bytes([1, 2, 3], 200))),
          isTrue);
      expect(registered, isNotNull);
      expect(TvOperations.instance.entries.single['state'], 'pronto');
    });
    test('insufficient free space refuses transfer and never registers it',
        () async {
      TvStorage.freeBytes = (_) async => 1;
      var registrations = 0, requests = 0;
      expect(
          await TvDownloads.save(track('song'),
              directory: () async => root,
              register: (_, __) async {
                registrations++;
              },
              resolve: (_) async => ResolvedMediaSource(
                  uri: Uri.parse('https://example.test/audio'),
                  isOffline: false),
              clientFactory: () => MockClient((_) async {
                    requests++;
                    return http.Response.bytes([1], 200);
                  })),
          isFalse);
      expect(registrations, 0);
      expect(requests, 0);
      expect(TvOperations.instance.entries.single['state'], 'errore');
    });
    test('interrupted operation state survives restart and is reconciled',
        () async {
      await TvOperations.instance
          .update('song', {'title': 'Brano', 'state': 'in corso'});
      await TvWorkspace.instance.open(root);
      await TvOperations.instance.reconcileInterrupted();
      expect(TvOperations.instance.entries.single['state'], 'interrotto');
    });
  });
}
