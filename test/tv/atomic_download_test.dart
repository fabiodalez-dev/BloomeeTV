import 'dart:async';
import 'dart:io';
import 'package:Bloomee/tv/services/atomic_audio_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bloomee-transfer-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  Future<File> save(http.Client client,
          {String id = 'song',
          int max = 100,
          bool Function()? cancelled,
          Duration timeout = const Duration(seconds: 2)}) =>
      AtomicAudioDownload.save(
          client: client,
          uri: Uri.parse('https://example.test/audio'),
          directory: directory,
          id: id,
          extension: 'audio',
          maxBytes: max,
          cancelled: cancelled,
          timeout: timeout);
  test('same-title recordings get different ID based filenames', () async {
    final client = MockClient((_) async => http.Response.bytes([1, 2, 3], 200));
    addTearDown(client.close);
    final first = await save(client, id: 'source::first');
    final second = await save(client, id: 'source::second');
    expect(first.path, isNot(second.path));
    expect(await first.readAsBytes(), [1, 2, 3]);
    expect(
        (await directory.list().toList())
            .where((e) => e.path.endsWith('.part')),
        isEmpty);
  });
  test(
      'truncated transfer keeps previous complete file and removes temporary file',
      () async {
    final good = MockClient((_) async => http.Response.bytes([7, 8, 9], 200));
    final file = await save(good);
    good.close();
    final broken = MockClient.streaming((_, __) async =>
        http.StreamedResponse(Stream.value([1]), 200, contentLength: 10));
    addTearDown(broken.close);
    await expectLater(save(broken), throwsA(isA<FileSystemException>()));
    expect(await file.readAsBytes(), [7, 8, 9]);
    expect(await directory.list().length, 1);
  });
  test('unknown-length stream enforces quota and cleans partial data',
      () async {
    final client = MockClient.streaming((_, __) async => http.StreamedResponse(
        Stream.fromIterable([
          [1, 2],
          [3, 4]
        ]),
        200));
    addTearDown(client.close);
    await expectLater(
        save(client, max: 3), throwsA(isA<FileSystemException>()));
    expect(await directory.list().length, 0);
  });
  test('cancelled transfer cannot publish a final file', () async {
    final client = MockClient((_) async => http.Response.bytes([1], 200));
    addTearDown(client.close);
    await expectLater(save(client, cancelled: () => true),
        throwsA(isA<FileSystemException>()));
    expect(await directory.list().length, 0);
  });
  test('HTTP failure and empty body never create downloadable audio', () async {
    for (final response in [http.Response('no', 403), http.Response('', 200)]) {
      final client = MockClient((_) async => response);
      await expectLater(save(client),
          throwsA(anyOf(isA<HttpException>(), isA<FileSystemException>())));
      client.close();
    }
    expect(await directory.list().length, 0);
  });
  test('stalled response times out without leaving a partial file', () async {
    final stream = StreamController<List<int>>();
    final client = MockClient.streaming(
        (_, __) async => http.StreamedResponse(stream.stream, 200));
    addTearDown(client.close);
    await expectLater(save(client, timeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()));
    await stream.close();
    expect(await directory.list().length, 0);
  });
  test('filename extensions cannot traverse paths', () {
    expect(() => AtomicAudioDownload.fileName('id', '../../x'),
        throwsArgumentError);
  });
}
