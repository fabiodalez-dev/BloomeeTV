import 'dart:convert';
import 'package:flutter/services.dart';

abstract class TvSecretStore {
  Future<Map<String, String>> read(String profile);
  Future<void> write(String profile, Map<String, String> values);
}

/// Android encrypts each bundle with an AES/GCM key held by Android Keystore.
/// There is deliberately no plaintext fallback on failure.
class AndroidTvSecretStore implements TvSecretStore {
  static const channel = MethodChannel('bloomee_tv/secure');
  @override
  Future<Map<String, String>> read(String profile) async {
    final raw =
        await channel.invokeMethod<String>('read', {'profile': profile});
    return raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
  }

  @override
  Future<void> write(String profile, Map<String, String> values) =>
      channel.invokeMethod<void>(
          'write', {'profile': profile, 'value': jsonEncode(values)});
}
