import 'package:Bloomee/services/player/sleep_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SleepTimer timer;
  late DateTime now;
  var stopped = 0;
  var volume = .8;
  setUp(() {
    now = DateTime(2026);
    stopped = 0;
    volume = .8;
    timer = SleepTimer(
        stop: () async {
          stopped++;
        },
        setVolume: (v) async {
          volume = v;
        },
        volume: () => volume,
        now: () => now);
  });
  tearDown(() => timer.dispose());
  test('duration fades, stops exactly once and restores original volume',
      () async {
    await timer.start(SleepMode.duration,
        duration: const Duration(seconds: 10),
        fadeDuration: const Duration(seconds: 4));
    now = now.add(const Duration(seconds: 8));
    await timer.tick();
    expect(volume, closeTo(.4, .001));
    now = now.add(const Duration(seconds: 2));
    await timer.tick();
    await timer.tick();
    expect(stopped, 1);
    expect(volume, .8);
    expect(timer.mode, SleepMode.off);
  });
  test('cancel during fade restores volume and cannot later stop playback',
      () async {
    await timer.start(SleepMode.duration, duration: const Duration(seconds: 4));
    await timer.tick();
    expect(volume, lessThan(.8));
    await timer.cancel();
    now = now.add(const Duration(minutes: 1));
    await timer.tick();
    expect(volume, .8);
    expect(stopped, 0);
  });
  test('end-track stops even if repeat points to identical song ID', () async {
    await timer.start(SleepMode.track, trackId: 'a');
    expect(await timer.beforeAdvance(nextTrackId: 'a', nextAlbumId: 'album'),
        isTrue);
    expect(stopped, 1);
  });
  test('end-album allows its tracks but stops before another album', () async {
    await timer.start(SleepMode.album, albumId: 'album');
    expect(await timer.beforeAdvance(nextTrackId: 'b', nextAlbumId: 'album'),
        isFalse);
    expect(await timer.beforeAdvance(nextTrackId: 'c', nextAlbumId: 'other'),
        isTrue);
    expect(stopped, 1);
  });
  test('pausing the shared timer suspends the deadline', () async {
    await timer.start(SleepMode.duration,
        duration: const Duration(seconds: 20));
    now = now.add(const Duration(seconds: 3));
    await timer.pause();
    now = now.add(const Duration(minutes: 5));
    await timer.tick();
    expect(stopped, 0);
    expect(timer.remaining.inSeconds, 17);
    timer.resume();
    now = now.add(const Duration(seconds: 17));
    await timer.tick();
    expect(stopped, 1);
  });
  test('rejects unavailable track, album and nonpositive duration', () async {
    await expectLater(timer.start(SleepMode.track), throwsArgumentError);
    await expectLater(timer.start(SleepMode.album), throwsArgumentError);
    await expectLater(timer.start(SleepMode.duration, duration: Duration.zero),
        throwsArgumentError);
  });
}
