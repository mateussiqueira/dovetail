import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows service creation has one native owner for app and daemon', () {
    final String root = Directory.current.parent.parent.path;
    final List<String> owners = <String>[];
    for (final String path in <String>[
      'toolkit/dovetail_privileged_helper/windows',
      'toolkit/dovetail_privileged_helper/rust/src',
      'toolkit/dovetail_privileged_daemon/rust/src/service/windows',
    ]) {
      final Directory directory = Directory('$root/$path');
      if (!directory.existsSync()) continue;
      for (final File file
          in directory.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.rs') && !file.path.endsWith('.cpp')) continue;
        final String code = file.readAsStringSync().replaceAll(
          RegExp(r'/\*[\s\S]*?\*/|//[^\n]*'),
          '',
        );
        if (RegExp(
          r'CreateServiceW\s*\(|\.create_service\s*\(',
        ).hasMatch(code)) {
          owners.add(file.path);
        }
      }
    }
    expect(
      owners,
      hasLength(1),
      reason: 'SCM creation must be shared: $owners',
    );
  });
}
