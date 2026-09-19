import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stom/main.dart';

void main() {
  // sqflite has no implementation in the unit-test environment, so the
  // dashboard's data load fails here; what this covers is that the app boots
  // to the home screen and degrades to its retry state instead of crashing.
  testWidgets('App starts on the home dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(StomApp());
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Stom'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
