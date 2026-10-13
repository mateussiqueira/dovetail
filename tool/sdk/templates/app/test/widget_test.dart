import 'package:dovetail/dovetail.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:{{name}}/main.dart';
import 'package:{{name}}/presentation/ui/pages/home_page.dart';

void main() {
  testWidgets('the app should render the home page from its routes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const {{camel_name}}App());
    await tester.pump();

    expect(find.byType(HomePage), findsOneWidget);
  });

  test('the dovetail runtime should answer from the resolved SDK', () {
    final ValidationFailure? failure = ValidationComposite(<FieldValidation>[
      ...Field('email').email().rules,
    ]).validate(<String, String?>{'email': 'not an email'});

    expect(failure, isA<FieldIsNotAnEmail>());
  });
}
