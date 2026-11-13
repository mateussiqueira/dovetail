import 'package:test/test.dart';

import '../../../tool/format_output.dart';

void main() {
  test(
    'Windows vendored cargokit paths keep the existing format exclusion',
    () {
      expect(
        ownUnformattedPaths(
          r'Changed tool\sdk\templates\bridge\cargokit\build_tool\lib\a.dart',
        ),
        isEmpty,
      );
    },
  );

  test(
    'Windows generated build output keeps the existing format exclusion',
    () {
      expect(
        ownUnformattedPaths(r'Changed toolkit\sample\build\a.dart'),
        isEmpty,
      );
    },
  );

  test('unformatted owned source is still reported on both path styles', () {
    expect(
      ownUnformattedPaths(
        'Changed toolkit/sample/lib/a.dart\n'
        r'Changed toolkit\sample\lib\b.dart',
      ),
      <String>['toolkit/sample/lib/a.dart', 'toolkit/sample/lib/b.dart'],
    );
  });

  test(
    'POSIX vendor exclusions and unrelated formatter output stay unchanged',
    () {
      expect(
        ownUnformattedPaths(
          'Changed tool/sdk/templates/bridge/cargokit/lib/a.dart\n'
          'Changed toolkit/sample/build/a.dart\n'
          'Formatted 2 files (2 changed).',
        ),
        isEmpty,
      );
    },
  );
}
