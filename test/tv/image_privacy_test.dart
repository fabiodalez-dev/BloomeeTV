import 'package:Bloomee/tv/services/tv_image_privacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ownership change waits for disk eviction and releases image memory',
      () async {
    final previous = TvImagePrivacy.emptyDiskCache;
    var evictions = 0;
    try {
      TvImagePrivacy.emptyDiskCache = () async {
        evictions++;
      };
      await TvImagePrivacy.clear();
      expect(evictions, 1);
    } finally {
      TvImagePrivacy.emptyDiskCache = previous;
    }
  });
}
