import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Only sanitized, bounded records can enter the diagnostic buffer/export.
class TvDiagnostics extends ChangeNotifier {
  static final instance = TvDiagnostics();
  final List<Map<String, String>> _events = [];
  List<Map<String, String>> get events => List.unmodifiable(_events);
  static String redact(String text) => text
      .replaceAll(
          RegExp(
              r'''["']?(cookie|set-cookie)["']?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\r\n}]+)''',
              caseSensitive: false),
          '[segreto omesso]')
      .replaceAll(
          RegExp(
              r'''["']?(authorization|proxy-authorization|cookie|set-cookie|password|token|api[-_]?key|sapisid|session)["']?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^,\r\n;}]+)''',
              caseSensitive: false),
          '[segreto omesso]')
      .replaceAll(RegExp(r'\bBearer\s+[^\s,;]+', caseSensitive: false),
          '[segreto omesso]')
      .replaceAll(RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'), '[indirizzo omesso]')
      .replaceAll(
          RegExp(r'(authorization|proxy-authorization)\s*[:=]\s*[^\r\n,}]+',
              caseSensitive: false),
          '[segreto omesso]')
      .replaceAll(
          RegExp(r'(cookie|set-cookie)\s*[:=]\s*[^\r\n}]+',
              caseSensitive: false),
          '[segreto omesso]')
      .replaceAll(RegExp(r'https?://[^\s"<>]+'), '[indirizzo omesso]')
      .replaceAll(
          RegExp(
              r'(authorization|cookie|password|token|api[-_]?key|sapisid|session)\s*[:=]\s*[^\s,;]+',
              caseSensitive: false),
          '[segreto omesso]')
      .replaceAll(RegExp(r'(/Users/|/data/user/|/storage/|[A-Z]:\\)[^\s]+'),
          '[percorso omesso]');
  void record(String area, Object message) {
    _events.add({
      'time': DateTime.now().toUtc().toIso8601String(),
      'area': redact(area),
      'message': redact(message.toString())
          .substring(0, redact(message.toString()).length.clamp(0, 800))
    });
    if (_events.length > 100) _events.removeAt(0);
    notifyListeners();
  }

  String export() => const JsonEncoder.withIndent('  ')
      .convert({'version': 1, 'events': _events});
  void clear() {
    _events.clear();
    notifyListeners();
  }
}
