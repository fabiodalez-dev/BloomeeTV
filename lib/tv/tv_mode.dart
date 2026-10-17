import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';

/// Rileva se l'app gira su Android TV / Google TV.
///
/// Su TV l'input arriva dal telecomando (D-pad), quindi ogni elemento
/// interattivo deve essere raggiungibile col focus e le scorciatoie da
/// tastiera pensate per il desktop (frecce = brano/volume) vanno disattivate.
class TvMode {
  TvMode._();

  static bool _isTv = false;

  static bool get isTv => _isTv;

  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _isTv = info.systemFeatures.contains('android.software.leanback') ||
          info.systemFeatures.contains('android.hardware.type.television');
    } catch (_) {
      _isTv = false;
    }
  }
}
