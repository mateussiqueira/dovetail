@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dovetail_cli/src/doctor/binary_report.dart';
import 'package:dovetail_cli/src/sdk/sdk_installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String executable;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('dovetail_windows_sdk_bin');
    final File source = File(p.join(root.path, 'probe.dart'))
      ..writeAsStringSync(
        "import 'dart:convert'; void main(List<String> args) {print(jsonEncode(args));}",
      );
    executable = p.join(root.path, 'native.exe');
    final ProcessResult compiled = Process.runSync(
      Platform.resolvedExecutable,
      <String>['compile', 'exe', source.path, '-o', executable],
    );
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}\n${compiled.stderr}',
    );
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  test(
    'the Windows SDK entry is discoverable and runs through its exe link',
    () {
      final String home = p.join(root.path, 'SDK Home');
      final String bin = p.join(root.path, 'User Bin');
      Directory(p.join(home, 'bin')).createSync(recursive: true);
      File(executable).copySync(p.join(home, 'bin', 'dovetail'));
      final Link link = SdkInstaller(home: home, binDir: bin).linkBin();
      final String? found = BinaryReport.findOnPath(
        bin,
        exists: (String path) => File(path).existsSync(),
      );
      expect(
        found,
        link.path,
        reason: 'Doctor must find the installed SDK entry',
      );
      expect(p.basename(link.path), 'dovetail.exe');
      const List<String> arguments = <String>[
        'two words',
        'a&b|c',
        '"quoted"',
        '',
      ];
      final ProcessResult ran = Process.runSync(found!, arguments);
      expect(ran.exitCode, 0, reason: '${ran.stdout}\n${ran.stderr}');
      expect(jsonDecode(ran.stdout as String), arguments);
    },
  );
}
