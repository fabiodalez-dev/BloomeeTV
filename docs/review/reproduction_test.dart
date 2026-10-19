// Diagnostic probes for the 2026-10-19 review.
// Run explicitly: flutter test --no-pub docs/review/reproduction_test.dart
// Both defects are now covered by passing regressions under test/player/.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Bloomee/services/player/player_error_handler.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/tv/ui/tv_widgets.dart';

void main() {
  testWidgets('pending retry must not survive manual reset', (tester) async {
    final handler = PlayerErrorHandler();
    addTearDown(handler.dispose);
    var retries = 0;
    handler.onRetryCurrentTrack = () {
      retries++;
    };
    const track = Track(
      id: 'test::1',
      title: 'Probe',
      artists: [],
      isExplicit: false,
      thumbnail: Artwork(url: '', layout: ImageLayout.square),
    );
    handler.registerAttempt(track.id);
    handler.handleError(PlayerErrorType.networkDropped, 'probe timeout', track);
    handler.resetCircuitBreaker();
    await tester.pump(const Duration(seconds: 2));
    expect(retries, 0, reason: 'Reset is used by stop() and manual skip.');
  });

  testWidgets('TV keyboard fits 854 by 480 logical pixels', (tester) async {
    tester.view.physicalSize = const Size(854, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showTvKeyboard(context, title: 'Cerca'),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
