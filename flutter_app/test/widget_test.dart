import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/main.dart';

void main() {
  testWidgets('MyApp renders the initial screen with the dark theme', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MyApp(initialScreen: Scaffold(body: Text('initial screen'))),
    );

    expect(find.text('initial screen'), findsOneWidget);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(app.theme?.brightness, Brightness.dark);
  });
}
