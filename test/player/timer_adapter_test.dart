import 'package:Bloomee/blocs/timer/timer_bloc.dart';
import 'package:Bloomee/services/player/sleep_timer.dart';
import 'package:Bloomee/utils/ticker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Bloomee/tv/tv_focus.dart';

void main() {
  test('legacy TimerBloc and TV controls share one timer', () async {
    var now = DateTime(2026);
    var stops = 0;
    final timer = SleepTimer(
        stop: () async {
          stops++;
        },
        setVolume: (_) async {},
        volume: () => 1,
        now: () => now);
    final bloc = TimerBloc(ticker: const Ticker(), timer: timer);
    bloc.add(const TimerStarted(duration: 60));
    await Future<void>.delayed(Duration.zero);
    expect(timer.mode, SleepMode.duration);
    expect(bloc.state, isA<TimerRunInProgress>());
    await timer.start(SleepMode.track, trackId: 'song');
    await Future<void>.delayed(Duration.zero);
    expect(timer.mode, SleepMode.track);
    bloc.add(const TimerReset());
    await Future<void>.delayed(Duration.zero);
    expect(timer.mode, SleepMode.off);
    await timer.start(SleepMode.duration, duration: const Duration(seconds: 1));
    now = now.add(const Duration(seconds: 2));
    await timer.tick();
    await Future<void>.delayed(Duration.zero);
    expect(stops, 1);
    expect(timer.mode, SleepMode.off);
    await bloc.close();
    timer.dispose();
  });
  test('arrow repeat speed preserves single key presses', () {
    final gate = TvKeyRepeatGate();
    final start = DateTime(2026);
    const interval = Duration(milliseconds: 240);
    expect(gate.allow(repeat: false, now: start, interval: interval), isTrue);
    expect(
        gate.allow(
            repeat: true,
            now: start.add(const Duration(milliseconds: 100)),
            interval: interval),
        isFalse);
    expect(
        gate.allow(
            repeat: false,
            now: start.add(const Duration(milliseconds: 110)),
            interval: interval),
        isTrue);
    expect(
        gate.allow(
            repeat: true,
            now: start.add(const Duration(milliseconds: 400)),
            interval: interval),
        isTrue);
  });
}
