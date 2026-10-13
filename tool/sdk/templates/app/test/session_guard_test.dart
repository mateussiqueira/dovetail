import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave_di/weave_di.dart';

import 'package:{{name}}/main.dart';
import 'package:{{name}}/main/di/root_module.dart';
import 'package:{{name}}/presentation/ui/pages/home_page.dart';
import 'package:{{name}}/presentation/ui/pages/welcome_page.dart';

void main() {
  setUpAll(() async {
    await (WeaveModuleRegistry()..register(rootModule())).installAll();
  });

  testWidgets('a fresh session should land on welcome, and starting it '
      'should open home', (WidgetTester tester) async {
    await tester.pumpWidget(const {{camel_name}}App());
    await tester.pumpAndSettle();

    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(WelcomePage), findsNothing);
  });
}
