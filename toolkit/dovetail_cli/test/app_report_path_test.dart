import 'dart:convert';
import 'dart:io';

import 'package:dovetail_cli/src/doctor/app_report.dart';
import 'package:dovetail_cli/src/doctor/project_report.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory home;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_app_paths');
    home = Directory(p.join(root.path, 'home'))..createSync();
    Directory(
      p.join(home.path, 'sdk', '0.1.0', 'packages'),
    ).createSync(recursive: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  ProjectNote reportFor(String path) {
    File(p.join(root.path, 'pubspec_overrides.yaml')).writeAsStringSync(
      'dependency_overrides:\n  dovetail:\n    path: $path\n',
    );
    return AppReport.of(root: root.path, home: home.path).notes.single;
  }

  const String windows = r'C:\Dovetail Home\sdk\0.1.0\packages\dovetail';
  final Map<String, String> installed = <String, String>{
    'POSIX': '/opt/dovetail/sdk/0.1.0/packages/dovetail',
    'Windows plain': windows,
    'Windows YAML quoted': jsonEncode(windows),
  };
  for (final MapEntry<String, String> entry in installed.entries) {
    test('doctor recognizes an installed SDK from ${entry.key} paths', () {
      final ProjectNote report = reportFor(entry.value);
      expect(report.finding, ProjectFinding.ready, reason: report.detail);
      expect(report.detail, '0.1.0');
    });
  }

  test('doctor names a missing Windows SDK version and its remedy', () {
    final ProjectNote report = reportFor(
      jsonEncode(windows.replaceFirst('0.1.0', '0.9.9')),
    );
    expect(report.finding, ProjectFinding.notConfigured);
    expect(report.detail, contains('0.9.9'));
    expect(report.detail, contains('upgrade'));
  });
}
