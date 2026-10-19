import 'dart:async';
import 'package:flutter/foundation.dart';

enum SleepMode { off, duration, track, album }

/// One timer shared by legacy TimerBloc and the TV player. No auto-play on expiry.
class SleepTimer extends ChangeNotifier {
  SleepTimer(
      {required this.stop,
      required this.setVolume,
      required this.volume,
      DateTime Function()? now})
      : now = now ?? DateTime.now;
  final Future<void> Function() stop;
  final Future<void> Function(double) setVolume;
  final double Function() volume;
  final DateTime Function() now;
  SleepMode mode = SleepMode.off;
  DateTime? deadline;
  Duration fade = const Duration(seconds: 8);
  String? _album;
  Duration? _pausedRemaining;
  bool get paused => _pausedRemaining != null;
  Future<void> _volumeWrites = Future.value();
  double? _originalVolume;
  Timer? _ticker;
  bool _expiring = false;
  int _generation = 0;
  Duration get remaining =>
      _pausedRemaining ??
      (deadline == null
          ? Duration.zero
          : deadline!.difference(now()).isNegative
              ? Duration.zero
              : deadline!.difference(now()));
  String get label => switch (mode) {
        SleepMode.off => 'Timer disattivato',
        SleepMode.duration =>
          'Spegnimento tra ${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}',
        SleepMode.track => 'Spegnimento a fine brano',
        SleepMode.album => 'Spegnimento a fine album',
      };
  Future<void> start(SleepMode value,
      {Duration? duration,
      String? trackId,
      String? albumId,
      Duration? fadeDuration}) async {
    await cancel();
    if (value == SleepMode.off) return;
    if (value == SleepMode.duration &&
        (duration == null || duration <= Duration.zero))
      throw ArgumentError('Durata non valida');
    if (value == SleepMode.track && (trackId == null || trackId.isEmpty))
      throw ArgumentError('Nessun brano');
    if (value == SleepMode.album && (albumId == null || albumId.isEmpty))
      throw ArgumentError('Nessun album');
    mode = value;
    _album = albumId;
    deadline = value == SleepMode.duration ? now().add(duration!) : null;
    fade = fadeDuration ?? const Duration(seconds: 8);
    _originalVolume = volume();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    notifyListeners();
  }

  Future<void> tick({Duration? trackRemaining, bool endOfAlbum = false}) async {
    if (mode == SleepMode.off || _expiring || paused) return;
    final left = mode == SleepMode.duration
        ? remaining
        : (mode == SleepMode.track || endOfAlbum)
            ? trackRemaining
            : null;
    if (left != null && fade > Duration.zero && left <= fade) {
      final generation = _generation;
      final level = (_originalVolume ?? volume()) *
          (left.inMilliseconds / fade.inMilliseconds).clamp(0, 1);
      await _writeVolume(level, generation);
    }
    if (mode == SleepMode.duration && remaining == Duration.zero)
      await expire();
    if (mode != SleepMode.off) notifyListeners();
  }

  Future<bool> beforeAdvance(
      {required String? nextTrackId,
      required String? nextAlbumId,
      bool wrapped = false}) async {
    if ((mode == SleepMode.track) ||
        (mode == SleepMode.album && (nextAlbumId != _album || wrapped))) {
      await expire();
      return true;
    }
    return false;
  }

  Future<void> expire() async {
    if (mode == SleepMode.off || _expiring) return;
    _expiring = true;
    final generation = _generation;
    _ticker?.cancel();
    try {
      await stop();
    } finally {
      if (_generation == generation) {
        mode = SleepMode.off;
        deadline = null;
        await _restoreVolume();
      }
      _expiring = false;
      notifyListeners();
    }
  }

  Future<void> _restoreVolume() async {
    final saved = _originalVolume;
    _originalVolume = null;
    if (saved != null) await _writeVolume(saved, _generation);
  }

  Future<void> cancel() async {
    _generation++;
    _ticker?.cancel();
    _ticker = null;
    mode = SleepMode.off;
    deadline = null;
    _pausedRemaining = null;
    await _restoreVolume();
    notifyListeners();
  }

  Future<void> _writeVolume(double level, int generation) {
    final write = _volumeWrites.then((_) async {
      if (generation == _generation) await setVolume(level);
    });
    _volumeWrites = write.catchError((Object _) {});
    return write;
  }

  Future<void> pause() async {
    if (mode != SleepMode.duration || paused) return;
    _pausedRemaining = remaining;
    await _restoreVolume();
    notifyListeners();
  }

  void resume() {
    final saved = _pausedRemaining;
    if (saved == null) return;
    deadline = now().add(saved);
    _pausedRemaining = null;
    _originalVolume = volume();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
