import 'package:Bloomee/core/adapters/track_adapter.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/services/bloomee_updater_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'media session publishes Cast display artwork, content ID and text metadata',
      () {
    const song = Track(
        id: 'source::song',
        title: 'Titolo',
        artists: [ArtistSummary(id: 'artist', name: 'Artista')],
        thumbnail: Artwork(
            url: 'https://example.test/cover.jpg',
            urlHigh: 'invalid',
            layout: ImageLayout.square),
        isExplicit: false);
    final item = trackToMediaItem(song,
        remoteArtUri: Uri.parse('http://tv.test:1234/cover/random'));
    expect(item.title, 'Titolo');
    expect(item.artist, 'Artista');
    expect(item.displaySubtitle, 'Artista');
    expect(item.artUri.toString(), 'https://example.test/cover.jpg');
    expect(item.extras!['android.media.metadata.DISPLAY_ICON_URI'],
        'http://tv.test:1234/cover/random');
    expect(item.extras!['android.media.metadata.MEDIA_URI'], 'source::song');
  });
  test('update build comparison preserves full integer values', () {
    expect(isUpdateAvailable('1.1.0', '1001', '1.1.0', '1002'), isTrue);
    expect(isUpdateAvailable('1.1.0', '2002', '1.1.0', '1003'), isFalse);
    expect(isUpdateAvailable('1.9.0', '9000', '2.0.0', '1'), isTrue);
    expect(
        isUpdateAvailable('1.1.0', '1001', '1.1.0', '1002', checkBuild: false),
        isFalse);
  });
  test('APK selection follows device ABI order and universal fallback', () {
    final data = {
      'assets': [
        for (final abi in ['arm64-v8a', 'armeabi-v7a', 'universal'])
          {
            'name': 'BloomeeTV-$abi.apk',
            'browser_download_url': 'https://example.test/BloomeeTV-$abi.apk'
          }
      ]
    };
    expect(extractUpUrl(data, platform: 'android', abis: ['armeabi-v7a']),
        endsWith('armeabi-v7a.apk'));
    expect(extractUpUrl(data, platform: 'android', abis: ['x86_64']),
        endsWith('universal.apk'));
    expect(
        extractUpUrl(
            {
              'assets': [
                {
                  'name': 'app-arm64-v8a.apk',
                  'browser_download_url': 'https://example.test/a.apk'
                }
              ]
            },
            platform: 'android',
            abis: ['armeabi-v7a']),
        isNull);
  });
}
