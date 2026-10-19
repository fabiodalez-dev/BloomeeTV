import 'dart:convert';
import 'dart:io';
import 'package:Bloomee/tv/services/tv_pairing_server.dart';
import 'package:Bloomee/tv/services/tv_workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class Network extends HttpOverrides {}

void main() {
  test(
      'profiles isolate preferences and remove guest files on exit and restart',
      () async {
    final root = await Directory.systemTemp.createTemp('bloomee-profiles-');
    addTearDown(() => root.delete(recursive: true));
    final profiles = TvProfiles();
    await profiles.open(root);
    profiles.onSwitch = (profile) =>
        TvWorkspace.instance.open(profiles.directoryFor(profile.id));
    await TvWorkspace.instance.set('favorite', 'Casa');
    final second = await profiles.create('Secondo');
    await profiles.select(second.id);
    expect(TvWorkspace.instance['favorite'], isNull);
    await TvWorkspace.instance.set('favorite', 'Secondo');
    await profiles.select('default');
    expect(TvWorkspace.instance['favorite'], 'Casa');
    final guest = await profiles.create('Ospite', guest: true);
    await profiles.select(guest.id);
    await profiles.select('default');
    expect(await profiles.directoryFor(guest.id).exists(), isFalse);
    final orphan = await profiles.create('Ospite temporaneo', guest: true);
    await File('${profiles.directoryFor(orphan.id).path}/cache')
        .writeAsString('private');
    final restart = TvProfiles();
    await restart.open(root);
    expect(await restart.directoryFor(orphan.id).exists(), isFalse);
  });
  test('failed profile switch preserves registry selection', () async {
    final root = await Directory.systemTemp.createTemp('bloomee-profiles-');
    addTearDown(() => root.delete(recursive: true));
    final profiles = TvProfiles();
    await profiles.open(root);
    final second = await profiles.create('Secondo');
    profiles.onSwitch = (_) async => throw StateError('failure');
    await expectLater(profiles.select(second.id), throwsStateError);
    expect(profiles.selectedId, 'default');
    expect(profiles.switching, isFalse);
  });
  test(
      'pairing requires code, bearer token and origin, accepts text only, and closes',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = TvPairingServer();
      final client = http.Client();
      try {
        await server.start(
            bind: InternetAddress.loopbackIPv4, advertisedHost: '127.0.0.1');
        final address = server.address!;
        expect(
            (await client.post(Uri.parse('$address/pair'),
                    body: jsonEncode({'code': 'wrong'})))
                .statusCode,
            403);
        final paired = await client.post(Uri.parse('$address/pair'),
            body: jsonEncode({'code': server.code}));
        final token = (jsonDecode(paired.body) as Map)['session'];
        final headers = {'Authorization': 'Bearer $token'};
        expect(
            (await client.post(Uri.parse('$address/text'),
                    body: '{"text":"Search"}'))
                .statusCode,
            403);
        expect(
            (await client.post(Uri.parse('$address/text'),
                    headers: {...headers, 'Origin': 'http://attacker.test'},
                    body: '{"text":"Search"}'))
                .statusCode,
            403);
        expect(
            (await client.post(Uri.parse('$address/text'),
                    headers: headers, body: '{"password":"secret"}'))
                .statusCode,
            400);
        expect(
            (await client.post(Uri.parse('$address/text'),
                    headers: headers, body: '{"text":"Search"}'))
                .statusCode,
            200);
        expect(server.takeText(), 'Search');
        expect(server.pendingText, isNull);
        await server.close();
        expect(server.active, isFalse);
        expect(server.session, isEmpty);
      } finally {
        client.close();
        await server.close();
        server.dispose();
      }
    }, Network());
  });
}
