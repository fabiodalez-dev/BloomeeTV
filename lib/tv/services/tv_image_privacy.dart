import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The notification service and TV artwork share the default image cache.
/// Purge it when ownership changes, including guest recovery after a restart.
class TvImagePrivacy {
  static Future<void> Function() emptyDiskCache =
      () => DefaultCacheManager().emptyCache();
  static Future<void> clear() async {
    await emptyDiskCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}
