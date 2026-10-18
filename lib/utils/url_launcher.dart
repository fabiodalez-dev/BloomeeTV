import 'dart:developer';

import 'package:Bloomee/tv/tv_mode.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> launch_Url(_url) async {
  if (!await openLink(_url)) {
    log('Could not launch $_url', name: "launch_Url");
  }
}

/// Apre un link esterno. Su Google TV di solito non c'è un browser, quindi
/// lo apro in una pagina web dentro l'app.
Future<bool> openLink(Uri url) async {
  if (TvMode.isTv && (url.scheme == 'http' || url.scheme == 'https')) {
    try {
      await const MethodChannel('bloomee_tv/voice')
          .invokeMethod('openWeb', {'url': url.toString()});
      return true;
    } catch (e) {
      log('openWeb: $e', name: 'openLink');
      return false;
    }
  }
  return launchUrl(url, mode: LaunchMode.externalApplication);
}
