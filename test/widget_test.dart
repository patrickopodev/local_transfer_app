import 'package:flutter_test/flutter_test.dart';

import 'package:local_transfer_app/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const LocalTransferApp());

    expect(find.text('Local Transfer'), findsOneWidget);
    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('No devices found yet — make sure the peer app is running on the same WiFi.'), findsNothing);
    expect(find.text('No transfers yet'), findsOneWidget);
  });
}