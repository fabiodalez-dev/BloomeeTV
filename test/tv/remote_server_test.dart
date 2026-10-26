import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:Bloomee/tv/services/tv_remote_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Network extends HttpOverrides {}

void main() {
  test(
      'music receiver requires PIN and token; commands execute and revoke on close',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = TvRemoteServer();
      final client = http.Client();
      final commands = <Map<String, dynamic>>[];
      server.readState = () => {'title': 'Brano', 'queue': [], 'playing': true};
      server.execute = (c) async => commands.add(c);
      try {
        await server.start(
            bind: InternetAddress.loopbackIPv4, advertisedHost: '127.0.0.1');
        final address = server.address!;
        expect((await client.get(Uri.parse('$address/state'))).statusCode, 401);
        expect(
            (await client.post(Uri.parse('$address/pair'),
                    body: '{"code":"000000"}'))
                .statusCode,
            403);
        final paired = await client.post(Uri.parse('$address/pair'),
            body: jsonEncode({'code': server.code}));
        expect(jsonDecode(paired.body)['protocol'], 1);
        final headers = {
          'Authorization': 'Bearer ${jsonDecode(paired.body)['session']}'
        };
        expect(
            jsonDecode((await client.get(Uri.parse('$address/state'),
                    headers: headers))
                .body)['title'],
            'Brano');
        expect(
            (await client.get(Uri.parse('$address/state'),
                    headers: {...headers, 'Origin': 'http://evil.test'}))
                .statusCode,
            403);
        for (final invalid in [
          {'action': 'volume', 'value': 2},
          {'action': 'queue', 'value': -1},
          {'action': 'seek', 'value': 1.5},
          {'action': 'play', 'password': 'secret'}
        ]) {
          expect(
              (await client.post(Uri.parse('$address/command'),
                      headers: headers, body: jsonEncode(invalid)))
                  .statusCode,
              400);
        }
        expect(commands, isEmpty);
        expect(
            (await client.post(Uri.parse('$address/command'),
                    headers: headers, body: '{"action":"next"}'))
                .statusCode,
            200);
        expect(commands.single, {'action': 'next'});
        final previousCode = server.code;
        await server.start(
            bind: InternetAddress.loopbackIPv4, advertisedHost: '127.0.0.1');
        expect(
            (await client.get(Uri.parse('${server.address}/state'),
                    headers: headers))
                .statusCode,
            401);
        expect(server.code, hasLength(previousCode.length));
      } finally {
        client.close();
        await server.close();
        server.dispose();
      }
    }, _Network());
  });
  test(
      'expired PIN cannot pair but an established session still controls music',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = TvRemoteServer();
      final client = http.Client();
      try {
        await server.start(
            bind: InternetAddress.loopbackIPv4,
            advertisedHost: '127.0.0.1',
            pairLifetime: const Duration(milliseconds: 100));
        final address = server.address!;
        final paired = await client.post(Uri.parse('$address/pair'),
            body: jsonEncode({'code': server.code}));
        final headers = {
          'Authorization': 'Bearer ${jsonDecode(paired.body)['session']}'
        };
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(
            (await client.post(Uri.parse('$address/pair'),
                    body: jsonEncode({'code': server.code})))
                .statusCode,
            403);
        expect(
            (await client.get(Uri.parse('$address/state'), headers: headers))
                .statusCode,
            200);
      } finally {
        client.close();
        await server.close();
        server.dispose();
      }
    }, _Network());
  });
  test(
      'revocation waits for an in-flight player operation before switching profile',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = TvRemoteServer();
      final client = http.Client();
      final started = Completer<void>(), finish = Completer<void>();
      server.execute = (_) async {
        started.complete();
        await finish.future;
      };
      try {
        await server.start(
            bind: InternetAddress.loopbackIPv4, advertisedHost: '127.0.0.1');
        final address = server.address!;
        final paired = await client.post(Uri.parse('$address/pair'),
            body: jsonEncode({'code': server.code}));
        final headers = {
          'Authorization': 'Bearer ${jsonDecode(paired.body)['session']}'
        };
        final request = client
            .post(Uri.parse('$address/command'),
                headers: headers, body: '{"action":"next"}')
            .then<void>((_) {}, onError: (_) {});
        await started.future;
        var closed = false;
        final closing = server.close().then((_) => closed = true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(server.active, isFalse);
        expect(closed, isFalse);
        finish.complete();
        await closing;
        await request;
        expect(closed, isTrue);
      } finally {
        if (!finish.isCompleted) finish.complete();
        client.close();
        await server.close();
        server.dispose();
      }
    }, _Network());
  });
  test(
      'catalog endpoint requires pairing, validates queries and returns TV metadata',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = TvRemoteServer(), client = http.Client();
      final queries = <Map<String, dynamic>>[];
      server.browse = (body) async {
        queries.add(body);
        return {
          'items': [
            {'id': '0-1', 'title': 'Song', 'kind': 'song'}
          ]
        };
      };
      try {
        await server.start(
            bind: InternetAddress.loopbackIPv4, advertisedHost: '127.0.0.1');
        final address = server.address!;
        expect(
            (await client.post(Uri.parse('$address/browse'),
                    body: '{"kind":"search","query":"song"}'))
                .statusCode,
            401);
        final pair = await client.post(Uri.parse('$address/pair'),
            body: jsonEncode({'code': server.code}));
        final info = jsonDecode(pair.body) as Map;
        expect(info['capabilities'], contains('catalog'));
        final headers = {'Authorization': 'Bearer ${info['session']}'};
        final page = await client.post(Uri.parse('$address/browse'),
            headers: headers, body: '{"kind":"search","query":"song"}');
        expect(page.statusCode, 200);
        expect(jsonDecode(page.body)['items'], hasLength(1));
        expect(queries, hasLength(1));
        expect(
            (await client.post(Uri.parse('$address/browse'),
                    headers: headers,
                    body: '{"kind":"collection","id":"http://evil"}'))
                .statusCode,
            400);
        expect(queries, hasLength(1));
      } finally {
        client.close();
        await server.close();
        server.dispose();
      }
    }, _Network());
  });
  test('command validator rejects unrecognized and out-of-range values', () {
    for (final command in [
      {'action': 'shell'},
      {'action': 'seek', 'value': double.infinity},
      {'action': 'shuffle', 'value': 1}
    ]) {
      expect(() => validateRemoteCommand(command), throwsFormatException);
    }
  });
}
