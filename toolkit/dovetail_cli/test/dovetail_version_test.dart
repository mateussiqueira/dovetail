import 'dart:io';

import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/repo_root.dart';

void main() {
  test('--version should report the version pubspec.yaml declares', () {
    final YamlMap pubspec =
        loadYaml(
              File(
                inRepo(<String>['toolkit', 'dovetail_cli', 'pubspec.yaml']),
              ).readAsStringSync(),
            )
            as YamlMap;

    expect(
      DovetailVersion.line.split(' ')[1],
      pubspec['version'],
      reason:
          'tool/build_release.sh reads the second word of --version and '
          'refuses the binary when it is not the pubspec version',
    );
  });
}
