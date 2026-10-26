import 'dart:convert';
import 'package:bloomee_remote/remote_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('address normalization refuses credentials and extra URL data', () {
    expect(
      parseTvAddress('192.168.1.5:18794/').toString(),
      'http://192.168.1.5:18794',
    );
    for (final input in [
      'http://user:pass@tv:80',
      'http://tv:80/?key=secret',
      'file:///tmp/tv',
      'http://tv:80/admin',
    ]) {
      expect(() => parseTvAddress(input), throwsA(isA<RemoteException>()));
    }
  });
  test('protocol pairs then authenticates state and commands', () async {
    final calls = <String>[];
    final remote = RemoteClient(
      Uri.parse('http://tv:18794'),
      client: MockClient((r) async {
        calls.add(r.url.path);
        expect(r.followRedirects, isFalse);
        if (r.url.path == '/pair') {
          expect(jsonDecode(r.body), {'code': '123456'});
          expect(r.headers.containsKey('Authorization'), isFalse);
          return http.Response(
            '{"session":"opaque","protocol":1,"name":"LG"}',
            200,
          );
        }
        expect(r.headers['Authorization'], 'Bearer opaque');
        if (r.url.path == '/command') {
          expect(jsonDecode(r.body), {'action': 'volume', 'value': 0.5});
        }
        return http.Response('{"playing":true,"ok":true}', 200);
      }),
    );
    await remote.pair('123 456');
    expect(remote.name, 'LG');
    expect((await remote.state())['playing'], isTrue);
    await remote.command('volume', 0.5);
    expect(calls, ['/pair', '/state', '/command']);
    remote.close();
  });
  test('legacy text-only receiver requires TV update', () async {
    final remote = RemoteClient(
      Uri.parse('http://tv:1234'),
      client: MockClient((_) async => http.Response('{"session":"old"}', 200)),
    );
    await expectLater(
      remote.pair('123456'),
      throwsA(
        isA<RemoteException>().having(
          (e) => e.message,
          'message',
          contains('solo testo'),
        ),
      ),
    );
    remote.close();
  });
  test('expired session and unreachable TV report actionable errors', () async {
    final remote = RemoteClient(
      Uri.parse('http://tv:1234'),
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    await expectLater(
      remote.state(),
      throwsA(
        isA<RemoteException>().having((e) => e.unauthorized, 'expired', isTrue),
      ),
    );
    remote.close();
    final offline = RemoteClient(
      Uri.parse('http://tv:1234'),
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      offline.state(),
      throwsA(
        isA<RemoteException>().having(
          (e) => e.message,
          'message',
          contains('Wi-Fi'),
        ),
      ),
    );
    offline.close();
  });
}
