// This is a basic Flutter widget test.
//
// To perform an interaction with your app, use the WidgetTester utility
// in the flutter_test package.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:city_app/main.dart';

void main() {
  testWidgets('App builds with bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const CityApp());
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
