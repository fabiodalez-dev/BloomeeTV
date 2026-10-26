import 'dart:convert';
import 'package:http/http.dart' as http;

class RemoteException implements Exception {
  const RemoteException(this.message, {this.unauthorized = false});
  final String message;
  final bool unauthorized;
  @override
  String toString() => message;
}

Uri parseTvAddress(String input) {
  final raw = input.trim();
  final uri = Uri.tryParse(raw.contains('://') ? raw : 'http://$raw');
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !['', '/'].contains(uri.path) ||
      uri.port <= 0) {
    throw const RemoteException(
      'Inserisci l’indirizzo mostrato sulla TV, con la porta.',
    );
  }
  return uri.replace(path: '');
}

class RemoteClient {
  RemoteClient(this.address, {http.Client? client})
    : _http = client ?? http.Client();
  final Uri address;
  final http.Client _http;
  String? _session;
  String name = 'Bloomee TV';
  Set<String> capabilities = {};
  bool get hasCatalog => capabilities.contains('catalog');
  bool _closed = false;

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_closed) throw const RemoteException('Collegamento chiuso');
    try {
      final req =
          http.Request(
              body == null ? 'GET' : 'POST',
              address.replace(path: path),
            )
            ..followRedirects = false
            ..headers['Content-Type'] = 'application/json';
      if (auth) req.headers['Authorization'] = 'Bearer $_session';
      if (body != null) req.body = jsonEncode(body);
      final response = await (() async {
        final stream = await _http.send(req);
        return http.Response.fromStream(stream);
      })().timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw RemoteException(
          path == '/pair'
              ? 'Codice errato o scaduto. Genera un nuovo codice sulla TV.'
              : 'Collegamento scaduto. Abbina nuovamente la TV.',
          unauthorized: auth,
        );
      }
      if (response.statusCode == 400) {
        final failure = jsonDecode(response.body);
        final message = failure is Map ? failure['error'] : null;
        throw RemoteException(
          message is String && message.length <= 500
              ? message
              : 'Richiesta non valida.',
        );
      }
      if (response.statusCode == 404 && path == '/browse') {
        throw const RemoteException(
          'Aggiorna Bloomee sulla TV per usare ricerca e playlist.',
        );
      }
      if (response.statusCode != 200) {
        throw RemoteException(
          response.statusCode == 409
              ? 'Attendi il comando precedente.'
              : 'La TV non ha eseguito il comando. Riprova.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return decoded;
    } on RemoteException {
      rethrow;
    } on FormatException {
      throw const RemoteException(
        'Aggiorna Bloomee sulla TV per usare il telecomando.',
      );
    } catch (_) {
      throw const RemoteException(
        'TV non raggiungibile. Controlla indirizzo, Wi-Fi e che Bloomee sia aperto.',
      );
    }
  }

  Future<void> pair(String code) async {
    final clean = code.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(clean)) {
      throw const RemoteException(
        'Inserisci il codice di 6 cifre mostrato sulla TV.',
      );
    }
    final data = await _request('/pair', body: {'code': clean}, auth: false);
    if (data['protocol'] != 1 ||
        data['session'] is! String ||
        (data['session'] as String).isEmpty) {
      throw const RemoteException(
        'Aggiorna Bloomee sulla TV: questa versione accetta solo testo.',
      );
    }
    _session = data['session'] as String;
    capabilities = (data['capabilities'] as List? ?? [])
        .whereType<String>()
        .toSet();
    name = data['name'] as String? ?? 'Bloomee TV';
  }

  Future<Map<String, dynamic>> state() => _request('/state');
  Future<void> command(String action, [Object? value]) async {
    await _request(
      '/command',
      timeout: const Duration(seconds: 45),
      body: {'action': action, if (value != null) 'value': value},
    );
  }

  Future<Map<String, dynamic>> browse(Map<String, dynamic> body) =>
      _request('/browse', body: body, timeout: const Duration(seconds: 45));

  void close() {
    _closed = true;
    _http.close();
  }
}
