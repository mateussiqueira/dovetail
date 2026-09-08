import 'package:dovetail_cli/src/app/app_template.dart';
import 'package:test/test.dart';

void main() {
  test('an explicit template that does not exist resolves to null', () {
    expect(AppTemplate.locate(explicit: '/does/not/exist'), isNull);
  });

  test('the repo walk should find tool/sdk/templates/app from the repo', () {
    expect(
      AppTemplate.locate(),
      isNotNull,
      reason:
          'os testes rodam de dentro do repo, e o template do app vive em '
          'tool/sdk/templates/app',
    );
  });
}
