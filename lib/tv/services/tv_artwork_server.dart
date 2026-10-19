import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Publishes only the current artwork on an opaque LAN URL. Cast clients cannot
/// attach Jellyfin authorization headers or read the TV's file:// artwork.
/// Credentials never enter the published URL and old capabilities are revoked.
class TvArtworkServer {
  TvArtworkServer({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  HttpServer? _server;
  http.Client? _request;
  List<int>? _bytes;
  String? _path, _host;
  String _mime = 'image/jpeg';
  int _generation = 0;
  Future<Uri?> publish(Uri source,
      {Map<String, String>? headers,
      InternetAddress? bind,
      String? advertisedHost}) async {
    final generation = ++_generation;
    _request?.close();
    _bytes = null;
    _path = null;
    final client = _clientFactory();
    _request = client;
    try {
      List<int> bytes;
      String mime;
      if (source.scheme == 'file') {
        final file = File.fromUri(source);
        if (await file.length() > 8 * 1024 * 1024) return null;
        bytes = await file.readAsBytes();
        mime = source.path.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
      } else {
        if (!['http', 'https'].contains(source.scheme)) return null;
        final response = await client
            .send(http.Request('GET', source)..headers.addAll(headers ?? {}))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200 ||
            (response.contentLength ?? 0) > 8 * 1024 * 1024) return null;
        mime =
            response.headers['content-type']?.split(';').first ?? 'image/jpeg';
        if (!['image/jpeg', 'image/png', 'image/webp', 'image/gif']
            .contains(mime)) return null;
        bytes = [];
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 10))) {
          if (generation != _generation) return null;
          bytes.addAll(chunk);
          if (bytes.length > 8 * 1024 * 1024) return null;
        }
      }
      if (bytes.isEmpty || generation != _generation) return null;
      if (_server == null) {
        final server =
            await HttpServer.bind(bind ?? InternetAddress.anyIPv4, 0);
        final addresses =
            (await NetworkInterface.list(type: InternetAddressType.IPv4))
                .expand((i) => i.addresses);
        final host = advertisedHost ??
            addresses.where((a) => !a.isLoopback).firstOrNull?.address;
        if (host == null || generation != _generation) {
          await server.close(force: true);
          return null;
        }
        _server = server;
        _host = host;
        _server!.listen((request) async {
          request.response.headers.set('Cache-Control', 'no-store');
          request.response.headers.set('X-Content-Type-Options', 'nosniff');
          if (request.method != 'GET' ||
              request.uri.path != _path ||
              _bytes == null) {
            request.response.statusCode = 404;
          } else {
            request.response.headers.contentType = ContentType.parse(_mime);
            request.response.contentLength = _bytes!.length;
            request.response.add(_bytes!);
          }
          await request.response.close();
        });
      }
      if (generation != _generation) return null;
      _bytes = bytes;
      _mime = mime;
      _path =
          '/cover/${List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      return Uri.parse('http://$_host:${_server!.port}$_path');
    } catch (_) {
      return null;
    } finally {
      client.close();
      if (identical(_request, client)) _request = null;
    }
  }

  Future<void> close() async {
    _generation++;
    _request?.close();
    _request = null;
    _bytes = null;
    _path = null;
    final server = _server;
    _server = null;
    _host = null;
    await server?.close(force: true);
  }
}
