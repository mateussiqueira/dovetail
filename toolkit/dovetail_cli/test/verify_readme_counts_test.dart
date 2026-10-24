import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final Directory source = Directory(
    Platform.environment['DOVETAIL_REPO_ROOT'] ??
        Directory.current.parent.parent.path,
  );
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('verify readme ');
    Directory('${fixture.path}/tool').createSync();
    Directory('${fixture.path}/toolkit').createSync();
    for (final String name in <String>[
      'verify.dart',
      'package_tool.dart',
      'format_output.dart',
    ]) {
      File('${source.path}/tool/$name').copySync('${fixture.path}/tool/$name');
    }
    File('${fixture.path}/tool/skip_baseline.json').writeAsStringSync(
      jsonEncode(<String, Object>{
        'packages': <String, Object>{
          'toolkit/contract': <String, Object>{
            'suites': <String, Object>{
              'test/contract_test.dart': <String, Object>{
                'declared': 2,
                'skips': <String, String>{
                  'native test': 'native host required',
                },
              },
            },
          },
        },
      }),
    );
  });

  tearDown(() => fixture.deleteSync(recursive: true));

  Future<ProcessResult> check(String text) async {
    File('${fixture.path}/README.md').writeAsStringSync(text);
    return Process.run(
      Platform.resolvedExecutable,
      <String>['tool/verify.dart', 'readme'],
      workingDirectory: fixture.path,
      environment: <String, String>{'DOVETAIL_REPO_ROOT': fixture.path},
    );
  }

  const String correct =
      '**Counted.** 2 Dart tests are declared in '
      '`tool/skip_baseline.json`, 1 of them skipped.';

  test('readme gate accepts the current English count contract', () async {
    expect((await check(correct)).exitCode, 0);
  });

  test('readme gate rejects stale declared counts', () async {
    expect((await check(correct.replaceFirst('2 Dart', '3 Dart'))).exitCode, 1);
  });

  test('readme gate rejects stale skipped counts', () async {
    expect(
      (await check(correct.replaceFirst('1 of them', '0 of them'))).exitCode,
      1,
    );
  });

  test(
    'readme gate does not accept unrelated numbers outside the count claim',
    () async {
      expect(
        (await check(
          correct.replaceFirst('**Counted.**', 'Elsewhere:'),
        )).exitCode,
        1,
      );
    },
  );

  test('readme gate keeps the existing Portuguese count contract', () async {
    expect(
      (await check('**2 testes Dart declarados, 1 pulados**')).exitCode,
      0,
    );
  });
}
