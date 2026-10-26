import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Opt-in music controls. Pairing expires after five minutes; an established
/// session lasts until the receiver closes (at most twelve hours).
class TvRemoteServer extends ChangeNotifier {
  HttpServer? _server;
  Timer? _expiry;
  String? address;
  String code = '';
  String _token = '';
  DateTime? pairingExpires;
  int _generation = 0, _failures = 0;
  bool _executing = false;
  Future<void>? _command;
  Map<String, dynamic> Function()? readState;
  Future<void> Function(Map<String, dynamic>)? execute;
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? browse;
  void Function()? resetCatalog;
  bool get active => _server != null;

  Future<void> start(
      {InternetAddress? bind,
      String? advertisedHost,
      Duration pairLifetime = const Duration(minutes: 5),
      Duration lifetime = const Duration(hours: 12)}) async {
    final closing = close();
    final generation = _generation;
    await closing;
    if (generation != _generation) return;
    final server = await HttpServer.bind(bind ?? InternetAddress.anyIPv4, 0);
    final host = advertisedHost ??
        (await NetworkInterface.list(type: InternetAddressType.IPv4))
            .expand((i) => i.addresses)
            .where((a) => !a.isLoopback)
            .firstOrNull
            ?.address;
    if (host == null || generation != _generation) {
      await server.close(force: true);
      if (host == null) {
        throw const SocketException('Collega la TV alla rete Wi-Fi');
      }
      return;
    }
    _server = server;
    address = 'http://$host:${server.port}';
    code = (100000 + Random.secure().nextInt(900000)).toString();
    _failures = 0;
    _token = List.generate(
            32,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    pairingExpires = DateTime.now().add(pairLifetime);
    _expiry = Timer(lifetime, () => unawaited(close()));
    server.listen((r) => _handle(r, generation));
    notifyListeners();
  }

  Future<void> _handle(HttpRequest r, int generation) async {
    r.response.headers.contentType = ContentType.json;
    r.response.headers.set('Cache-Control', 'no-store');
    r.response.headers.set('X-Content-Type-Options', 'nosniff');
    void reply(int status, Object data) {
      try {
        r.response.statusCode = status;
        r.response.write(jsonEncode(data));
      } on HttpException {
        // A closed receiver or disconnected phone cannot receive a reply.
      } on SocketException {
        // The command may have completed while the phone left the Wi-Fi.
      }
    }

    try {
      // This is a native client API. Browser origins have no access.
      if (r.headers.value('origin') != null ||
          generation != _generation ||
          !active) {
        reply(403, {'error': 'Accesso negato'});
        return;
      }
      if (r.uri.path == '/pair' && r.method == 'POST') {
        final body = await _body(r);
        if (generation != _generation ||
            !active ||
            _failures >= 5 ||
            !DateTime.now().isBefore(pairingExpires!) ||
            body['code'] != code) {
          _failures++;
          reply(403, {
            'error': 'Codice errato o scaduto. Riapri il collegamento sulla TV.'
          });
          return;
        }
        reply(200, {
          'session': _token,
          'protocol': 1,
          'capabilities': ['catalog'],
          'platform': 'android',
          'name': 'Bloomee Android TV'
        });
        return;
      }
      if (_token.isEmpty ||
          r.headers.value('authorization') != 'Bearer $_token') {
        reply(401, {'error': 'Abbina nuovamente la TV'});
        return;
      }
      if (r.method == 'GET' && r.uri.path == '/state') {
        reply(200, readState?.call() ?? {'queue': [], 'playing': false});
      } else if (r.method == 'POST' && r.uri.path == '/browse') {
        final body = await _body(r);
        validateRemoteBrowse(body);
        if (generation != _generation || !active)
          throw const RemoteApiException('Collegamento chiuso.');
        final result = await browse!(body);
        if (generation == _generation && active) reply(200, result);
      } else if (r.method == 'POST' && r.uri.path == '/command') {
        final body = await _body(r);
        validateRemoteCommand(body);
        if (generation != _generation || !active) {
          reply(401, {'error': 'Collegamento chiuso'});
        } else if (_executing) {
          reply(409, {'error': 'Attendi il comando precedente'});
        } else if (execute == null) {
          reply(503, {'error': 'Player non disponibile'});
        } else {
          _executing = true;
          try {
            _command = execute!(body);
            await _command;
            reply(200, {'ok': true});
          } finally {
            _executing = false;
            _command = null;
          }
        }
      } else {
        reply(404, {'error': 'Percorso non disponibile'});
      }
    } on RemoteApiException catch (e) {
      reply(400, {'error': e.message});
    } on FormatException {
      reply(400, {'error': 'Comando non valido'});
    } catch (_) {
      reply(
          503, {'error': 'Comando non riuscito. Verifica il player sulla TV.'});
    } finally {
      try {
        await r.response.close();
      } catch (_) {
        // Closing the receiver also closes in-flight HTTP responses.
      }
    }
  }

  Future<Map<String, dynamic>> _body(HttpRequest r) async {
    if (r.contentLength < 0 || r.contentLength > 2048) {
      throw const FormatException();
    }
    final bytes = <int>[];
    await for (final chunk in r.timeout(const Duration(seconds: 5))) {
      bytes.addAll(chunk);
      if (bytes.length > 2048) throw const FormatException();
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) throw const FormatException();
    return value;
  }

  Future<void> close() async {
    _generation++;
    resetCatalog?.call();
    _expiry?.cancel();
    _expiry = null;
    final server = _server;
    _server = null;
    address = null;
    code = _token = '';
    pairingExpires = null;
    await server?.close(force: true);
    // A profile switch waits for any already-started player operation before
    // replacing its database and queue. Revocation rejects new operations now.
    final command = _command;
    if (command != null) {
      try {
        await command;
      } catch (_) {}
    }
    notifyListeners();
  }
}

void validateRemoteCommand(Map<String, dynamic> body) {
  if (body.keys.any((k) => !['action', 'value'].contains(k))) {
    throw const FormatException();
  }
  final action = body['action'], value = body['value'];
  if (['play', 'pause', 'next', 'previous'].contains(action) &&
      body.length == 1) {
    return;
  }
  if (validCatalogCommand(action, value)) return;
  if (action == 'shuffle' && value is bool) return;
  if (action == 'repeat' && ['off', 'all'].contains(value)) return;
  if (action == 'volume' &&
      value is num &&
      value.isFinite &&
      value >= 0 &&
      value <= 1) {
    return;
  }
  if (action == 'seek' && value is int && value >= 0 && value <= 604800000) {
    return;
  }
  if (action == 'queue' && value is int && value >= 0 && value < 100000) return;
  throw const FormatException();
}

final tvRemote = TvRemoteServer();

class RemoteApiException implements Exception {
  const RemoteApiException(this.message);
  final String message;
}

bool _remoteId(dynamic value) =>
    value is String &&
    RegExp(r'^[0-9]+-[0-9]+$').hasMatch(value) &&
    value.length < 80;
bool validCatalogCommand(dynamic action, dynamic value) =>
    ['playItem', 'enqueueItem', 'shuffleItem'].contains(action) &&
    _remoteId(value);

void validateRemoteBrowse(Map<String, dynamic> body) {
  if (body.keys.any((k) =>
      !['kind', 'query', 'filter', 'source', 'id', 'cursor'].contains(k)))
    throw const FormatException();
  if (body['cursor'] != null) {
    if (body.length == 1 && _remoteId(body['cursor'])) return;
    throw const FormatException();
  }
  if (!['search', 'playlists', 'collection'].contains(body['kind']))
    throw const FormatException();
  if (body['kind'] == 'search' &&
      (body['query'] is! String ||
          (body['query'] as String).trim().isEmpty ||
          (body['query'] as String).length > 160))
    throw const FormatException();
  if (body['filter'] != null &&
      !['songs', 'playlists'].contains(body['filter']))
    throw const FormatException();
  if (body['source'] != null &&
      !['all', 'youtube', 'jellyfin', 'local'].contains(body['source']))
    throw const FormatException();
  if (body['kind'] == 'collection' && !_remoteId(body['id']))
    throw const FormatException();
}
