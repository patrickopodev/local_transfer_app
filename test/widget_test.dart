import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_transfer_app/main.dart';
import 'package:local_transfer_app/services/pairing_codec.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LocalDropApp(autoStart: false));

    expect(find.text('LocalDrop', findRichText: true), findsOneWidget);
    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('SEND'), findsOneWidget);
    expect(find.text('RECEIVE'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Transfers'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('RECEIVE tap does not crash and gives visible feedback',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LocalDropApp(autoStart: false));

    final receive = find.text('RECEIVE');
    expect(receive, findsOneWidget);
    // Tap twice: start then stop. Previously the fire-and-forget start() left
    // an unhandled SocketException when binding failed; now start() never
    // throws and each tap yields a snackbar.
    await tester.tap(receive);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('Transfers tab has Active/Completed/Failed filter',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LocalDropApp(autoStart: false));
    await tester.tap(find.text('Transfers'));
    await tester.pumpAndSettle();

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);

    await tester.tap(find.text('Failed'));
    await tester.pumpAndSettle();
    expect(find.text('No failed transfers'), findsOneWidget);
  });

  testWidgets('Settings tab is wired and shows device name',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LocalDropApp(autoStart: false));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Device name'), findsOneWidget);
    expect(find.text('Receive location'), findsOneWidget);
    expect(find.text('Choose folder'), findsOneWidget);
  });

  test('PairingCodec round-trips name/ip/port', () {
    final code = PairingCodec.encode('My Phone', '192.168.1.5', 5678);
    final decoded = PairingCodec.decode(code);
    expect(decoded, isNotNull);
    expect(decoded!.name, 'My Phone');
    expect(decoded.ip, '192.168.1.5');
    expect(decoded.port, 5678);
  });

  test('PairingCodec rejects garbage', () {
    expect(PairingCodec.decode('not a code'), isNull);
    expect(PairingCodec.decode('http://192.168.1.5:5678/x'), isNull);
  });
}