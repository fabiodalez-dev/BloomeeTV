import 'dart:io';
import 'dart:typed_data';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';
import 'package:Bloomee/services/db/dao/download_dao.dart';
import 'package:Bloomee/services/db/dao/playlist_dao.dart';
import 'package:Bloomee/main.dart' as app;
import 'package:Bloomee/services/player/sleep_timer.dart';
import 'package:Bloomee/tv/services/tv_cast_service.dart';
import 'package:Bloomee/tv/tv_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Run explicitly on an authorized TV. The test restores queue/order, position,
/// playback, repeat, shuffle and ReplayGain preference after exercising them.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('TV queue editing, shared timer, ReplayGain and Cast session',
      (tester) async {
    await app.main();
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(seconds: 1));
      try {
        if (app.bloomeePlayerCubit.bloomeePlayer.isPlayerHealthy) break;
      } catch (_) {}
    }
    expect(TvMode.isTv, isTrue);
    final player = app.bloomeePlayerCubit.bloomeePlayer;
    final original = player.queueTracks;
    final originalIndex = player.currentQueueIndex;
    final originalPosition = player.engine.position;
    final wasPlaying = player.engine.playing;
    final originalLoop = player.loopMode.value;
    final originalShuffle = player.shuffleMode.value;
    final originalGain = player.engine.loudnessEnabled;
    final directory =
        await Directory('${DBProvider.appSuppDir}/diagnostic-test-audio')
            .create(recursive: true);
    final tracksDao = TrackDAO(DBProvider.db);
    final downloads = DownloadDAO(
        DBProvider.db, tracksDao, PlaylistDAO(DBProvider.db, tracksDao));
    final fixture = <Track>[];
    for (var i = 0; i < 3; i++) {
      final bytes = ByteData(44 + 16000 * 30 * 2);
      void text(int offset, String value) {
        for (var j = 0; j < value.length; j++) {
          bytes.setUint8(offset + j, value.codeUnitAt(j));
        }
      }

      text(0, 'RIFF');
      bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
      text(8, 'WAVE');
      text(12, 'fmt ');
      bytes.setUint32(16, 16, Endian.little);
      bytes.setUint16(20, 1, Endian.little);
      bytes.setUint16(22, 1, Endian.little);
      bytes.setUint32(24, 16000, Endian.little);
      bytes.setUint32(28, 32000, Endian.little);
      bytes.setUint16(32, 2, Endian.little);
      bytes.setUint16(34, 16, Endian.little);
      text(36, 'data');
      bytes.setUint32(40, bytes.lengthInBytes - 44, Endian.little);
      await File('${directory.path}/$i.wav')
          .writeAsBytes(bytes.buffer.asUint8List());
      final track = Track(
          id: 'local::codex-tv-test-$i',
          title: 'Prova TV ${i + 1}',
          artists: const [ArtistSummary(id: 'test', name: 'Diagnostica')],
          thumbnail: const Artwork(url: '', layout: ImageLayout.square),
          isExplicit: false,
          durationMs: BigInt.from(30000));
      fixture.add(track);
      await downloads.putDownloadRecord(
          fileName: '$i.wav', filePath: directory.path, track: track);
    }
    await player.updateQueueTracks(fixture, doPlay: true);
    final fixtureIndex = player.currentQueueIndex;
    try {
      await player.pause();
      final order = List.generate(fixture.length, (i) => i);
      final first = order.removeAt(1);
      order.insert(2, first);
      await player.editQueueTracks(
          fixture, order.map((i) => fixture[i]).toList(), order);
      expect(player.currentTrackInfo.id, fixture[fixtureIndex].id);
      expect(player.queueTracks[1].id, fixture[2].id);
      final edited = player.queueTracks;
      final inverse = List.generate(fixture.length, (i) => order.indexOf(i));
      await player.editQueueTracks(edited, fixture, inverse);
      expect(player.currentQueueIndex, fixtureIndex);
      expect(player.queueTracks.map((t) => t.id), fixture.map((t) => t.id));
      await player.play();
      await tester.pump(const Duration(seconds: 3));
      expect(player.engine.playing, isTrue);
      expect(player.mediaItem.value?.title, player.currentTrackInfo.title);
      expect(
          player.mediaItem.value?.extras?['android.media.metadata.MEDIA_URI'],
          player.currentTrackInfo.id);
      await player.engine.setLoudnessEnabled(true);
      expect(await player.engine.loudnessModes(), ['track', 'track']);
      await player.engine.setLoudnessEnabled(false);
      expect(await player.engine.loudnessModes(), ['no', 'no']);
      expect(await TvCastService.status(), contains('sessione audio'));
      await player.sleepTimer.start(SleepMode.duration,
          duration: const Duration(seconds: 2),
          fadeDuration: const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 4));
      expect(player.sleepTimer.mode, SleepMode.off);
      expect(player.engine.playing, isFalse);
    } finally {
      await player.sleepTimer.cancel();
      await player.engine.setLoudnessEnabled(originalGain);
      await player.stop();
      await player.editQueueTracks(
          player.queueTracks, original, List.filled(original.length, -1));
      if (original.isNotEmpty) {
        await player.updateQueueTracks(original,
            startIndex: originalIndex, doPlay: true);
        await player.seek(originalPosition);
      }
      player.setLoopMode(originalLoop);
      await player.shuffle(originalShuffle);
      if (!wasPlaying) await player.pause();
      for (final track in fixture) {
        await downloads.removeDownloadRecord(track.id);
        await tracksDao.purgeOrphanTrack(track.id);
      }
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
