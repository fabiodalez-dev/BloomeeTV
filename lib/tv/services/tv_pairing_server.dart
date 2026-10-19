import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Temporary LAN text input. Credentials are intentionally never accepted over
/// this HTTP MVP. A new code/session is generated for every opening.
class TvPairingServer extends ChangeNotifier {
  HttpServer? _server;
  Timer? _expiry;
  String code = '', session = '';
  String? address, pendingText;
  DateTime? expires;
  int _failures = 0, _messages = 0;
  bool get active => _server != null;
  String _random(int length) => List.generate(length,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
  Future<void> start(
      {InternetAddress? bind,
      String? advertisedHost,
      Duration lifetime = const Duration(minutes: 5)}) async {
    await close();
    code = (100000 + Random.secure().nextInt(900000)).toString();
    session = _random(32);
    _failures = 0;
    _messages = 0;
    pendingText = null;
    _server = await HttpServer.bind(bind ?? InternetAddress.anyIPv4, 0);
    final interfaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4);
    final host = advertisedHost ??
        interfaces
            .expand((i) => i.addresses)
            .where((a) => !a.isLoopback)
            .firstOrNull
            ?.address;
    if (host == null) {
      await close();
      throw const SocketException('Nessuna rete locale disponibile');
    }
    address = 'http://$host:${_server!.port}';
    expires = DateTime.now().add(lifetime);
    _expiry = Timer(lifetime, () => close());
    _server!.listen(_handle);
    notifyListeners();
  }

  Future<void> _handle(HttpRequest request) async {
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.headers.set('X-Content-Type-Options', 'nosniff');
    request.response.headers.set('Content-Security-Policy',
        "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors 'none'");
    try {
      if (request.method == 'GET' && request.uri.path == '/') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_page);
      } else if (request.method == 'POST') {
        final origin = request.headers.value('origin');
        if (origin != null && origin != address) {
          request.response.statusCode = 403;
          return;
        }
        if (request.contentLength < 0 || request.contentLength > 2048) {
          request.response.statusCode = 413;
          return;
        }
        final body = jsonDecode(await utf8.decoder
            .bind(request)
            .join()
            .timeout(const Duration(seconds: 5))) as Map;
        if (request.uri.path == '/pair') {
          if (_failures >= 8 || body['code'] != code) {
            _failures++;
            request.response.statusCode = 403;
            return;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'session': session}));
        } else if (request.uri.path == '/text') {
          if (request.headers.value('authorization') != 'Bearer $session' ||
              ++_messages > 50) {
            request.response.statusCode = 403;
            return;
          }
          final text = body['text'];
          if (text is! String ||
              text.length > 500 ||
              body.keys.any((k) => k != 'text')) {
            request.response.statusCode = 400;
            return;
          }
          pendingText = text;
          notifyListeners();
          request.response.write('Inviato: conferma sulla TV');
        } else {
          request.response.statusCode = 404;
        }
      } else {
        request.response.statusCode = 405;
      }
    } catch (_) {
      request.response.statusCode = 400;
    } finally {
      await request.response.close();
    }
  }

  String? takeText() {
    final text = pendingText;
    pendingText = null;
    notifyListeners();
    return text;
  }

  Future<void> close() async {
    _expiry?.cancel();
    _expiry = null;
    final server = _server;
    _server = null;
    session = '';
    code = '';
    address = null;
    expires = null;
    pendingText = null;
    await server?.close(force: true);
    notifyListeners();
  }

  static const _page =
      '''<!doctype html><html lang="it"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Bloomee TV</title>
<style>body{font:20px system-ui;max-width:36em;margin:2em auto;padding:1em;background:#17121f;color:#f4eef8}input,button{font:inherit;padding:.7em;margin:.3em 0;box-sizing:border-box;width:100%}</style>
<h1>Scrivi sulla TV</h1><p>Solo testo di ricerca e indirizzi pubblici. Non inviare password, cookie o chiavi API.</p>
<input id="code" inputmode="numeric" placeholder="Codice di 6 cifre sulla TV"><button onclick="pair()">Abbina</button>
<input id="text" maxlength="500" placeholder="Artista, album o indirizzo pubblico"><button onclick="send()">Invia testo</button><p id="status"></p>
<script>let session='';async function pair(){let r=await fetch('/pair',{method:'POST',body:JSON.stringify({code:document.getElementById('code').value})});if(r.ok){session=(await r.json()).session;statusText('Abbinato')}else statusText('Codice non valido o scaduto')}async function send(){let r=await fetch('/text',{method:'POST',headers:{Authorization:'Bearer '+session},body:JSON.stringify({text:document.getElementById('text').value})});statusText(r.ok?'Conferma il testo sulla TV':'Sessione non valida')}function statusText(t){document.getElementById('status').textContent=t}</script></html>''';
}

final tvPairing = TvPairingServer();
