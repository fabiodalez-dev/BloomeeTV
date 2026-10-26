import 'package:bloomee_remote/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('connection screen explains both TVs and validates pairing', (
    tester,
  ) async {
    await tester.pumpWidget(const RemoteApp());
    await tester.pumpAndSettle();
    expect(find.text('Bloomee Remote'), findsOneWidget);
    expect(find.textContaining('LG webOS:'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '192.168.1.50:18794');
    await tester.tap(find.text('Collega TV'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Inserisci il codice di 6 cifre'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('small phone and large text remain scrollable', (tester) async {
    tester.view.physicalSize = const Size(640, 960);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: RemoteApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
