import 'package:flutter_test/flutter_test.dart';

import 'package:stom/main.dart';

void main() {
  testWidgets('App starts on the patient list screen', (WidgetTester tester) async {
    await tester.pumpWidget(StomApp());
    await tester.pumpAndSettle();

    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('Add new'), findsOneWidget);
  });
}
