import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_transfer_app/main.dart';

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
}