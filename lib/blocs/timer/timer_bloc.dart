import 'dart:async';
import 'package:Bloomee/services/player/sleep_timer.dart';
import 'package:Bloomee/utils/ticker.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
part 'timer_event.dart';
part 'timer_state.dart';

/// Legacy UI is an adapter over the very same timer used by the TV player.
class TimerBloc extends Bloc<TimerEvent, TimerState> {
  final SleepTimer _timer;
  TimerBloc({required Ticker ticker, required SleepTimer timer})
      : _timer = timer,
        super(const TimerInitial(0)) {
    on<TimerStarted>((event, emit) async {
      await _timer.start(SleepMode.duration,
          duration: Duration(seconds: event.duration));
      _sync();
    });
    on<TimerPaused>((event, emit) async {
      await _timer.pause();
      emit(TimerRunPause(_timer.remaining.inSeconds));
    });
    on<TimerResumed>((event, emit) {
      _timer.resume();
      _sync();
    });
    on<TimerReset>((event, emit) async {
      await _timer.cancel();
      emit(const TimerInitial(0));
    });
    on<TimerStopped>((event, emit) async {
      await _timer.cancel();
      emit(const TimerRunStopped());
    });
    on<_TimerTicked>((event, emit) {
      if (_timer.paused)
        emit(TimerRunPause(event.duration));
      else if (_timer.mode == SleepMode.duration)
        emit(TimerRunInProgress(event.duration));
      else if (state is TimerRunInProgress || state is TimerRunPause)
        emit(const TimerRunComplete());
    });
    _timer.addListener(_sync);
  }
  void _sync() {
    if (!isClosed) add(_TimerTicked(duration: _timer.remaining.inSeconds));
  }

  @override
  Future<void> close() {
    _timer.removeListener(_sync);
    return super.close();
  }
}
