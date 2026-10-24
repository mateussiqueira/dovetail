@TestOn('windows')
library;

import 'dart:io';

import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';

void main() {
  test('doctor compiles a payload with an installed native NSIS', () async {
    if (Process.runSync('where', <String>['makensis']).exitCode != 0) {
      markTestSkipped('NSIS is not installed');
      return;
    }
    final ToolReport report = await const NsisProbe().probe();
    expect(report.status, ToolStatus.usable, reason: report.detail);
  });
}
