import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_distribuidora/main.dart';

void main() {
  testWidgets('Login screen is shown with app title', (WidgetTester tester) async {
    await tester.pumpWidget(const AppDistribuidora());

    expect(find.text('App Distribuidora'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });
}
