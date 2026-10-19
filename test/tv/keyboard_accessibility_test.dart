import 'package:Bloomee/tv/ui/tv_widgets.dart';
import 'package:Bloomee/tv/tv_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
      WidgetTester tester, String initial, ValueChanged<String> result,
      {double scale = 1}) async {
    tester.view.physicalSize = const Size(854, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      final value = await showTvKeyboard(context,
                          title: 'Cerca', initial: initial);
                      if (value != null) result(value);
                    },
                    child: const Text('Apri'))))));
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('keyboard fits small TV viewport with 150 percent text',
      (tester) async {
    await open(tester, '', (_) {}, scale: 1.5);
    expect(tester.takeException(), isNull);
  });
  testWidgets('backspace removes whole grapheme clusters', (tester) async {
    String? result;
    await open(tester, 'A👨‍👩‍👧‍👦B', (v) => result = v);
    await tester.tap(find.text('Cancella'));
    await tester.pump();
    await tester.tap(find.text('Cancella'));
    await tester.pump();
    await tester.tap(find.text('Fatto'));
    await tester.pumpAndSettle();
    expect(result, 'A');
  });
  testWidgets('cursor allows inserting into the middle of an existing value',
      (tester) async {
    String? result;
    await open(tester, 'ac', (v) => result = v);
    await tester.tap(find.text('Cursore ←'));
    await tester.pump();
    await tester.tap(find.text('b'));
    await tester.pump();
    await tester.tap(find.text('Fatto'));
    await tester.pumpAndSettle();
    expect(result, 'abc');
  });
  testWidgets(
      'custom control exposes semantic action and accepts OK and pointer',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var activations = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TvFocusable(
                autofocus: true,
                semanticLabel: 'Riproduci brano',
                onTap: () => activations++,
                child: const Text('Play')))));
    await tester.pump();
    expect(find.bySemanticsLabel('Riproduci brano'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(activations, 2);
    semantics.dispose();
  });
}
