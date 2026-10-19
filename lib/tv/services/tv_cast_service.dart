import 'package:flutter/services.dart';
import 'tv_diagnostics.dart';

/// Cast transport remains native; the same Dart player resolves supported IDs.
class TvCastService {
  static const channel = MethodChannel('bloomee_tv/cast');
  static Future<void> initialize(
      Future<void> Function(String id, Duration position) load) async {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'load') throw MissingPluginException();
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final id = args['id'] as String?;
      if (id == null || id.isEmpty || id.length > 4096)
        throw PlatformException(
            code: 'unsupported', message: 'Contenuto non supportato');
      try {
        await load(id,
            Duration(milliseconds: (args['positionMs'] as num?)?.toInt() ?? 0));
      } catch (e) {
        TvDiagnostics.instance.record('Cast', e);
        throw PlatformException(
            code: 'load', message: 'Impossibile riprodurre questo contenuto');
      }
    });
    try {
      await channel.invokeMethod<void>('ready');
    } on MissingPluginException {/* Non-Android platforms. */}
  }

  static Future<String> status() async {
    try {
      return await channel.invokeMethod<String>('status') ??
          'Cast non disponibile';
    } on MissingPluginException {
      return 'Cast non disponibile su questa piattaforma';
    }
  }
}
