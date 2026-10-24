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
    'the Windows ZIP SDK entry is discoverable and preserves literal arguments',
    () async {
      final String home = p.join(root.path, 'SDK Home');
      final String bin = p.join(root.path, 'User Bin');
      final String payload = p.join(root.path, 'Archive Payload');
      Directory(p.join(payload, 'bin')).createSync(recursive: true);
      File(executable).copySync(p.join(payload, 'bin', 'dovetail.exe'));
      final File archive = File(p.join(root.path, 'sdk.zip'));
      final ProcessResult packed = Process.runSync('tar', <String>[
        '-a',
        '-cf',
        archive.path,
        '-C',
        payload,
        'bin',
      ]);
      expect(packed.exitCode, 0, reason: '${packed.stderr}');
      expect(archive.readAsBytesSync().take(2), <int>[0x50, 0x4b]);
      final SdkInstaller installer = SdkInstaller(home: home, binDir: bin);
      final String installed = await installer.extract(archive);
      expect(installed, p.join(home, 'bin', 'dovetail.exe'));
      expect(File(installed).existsSync(), isTrue);
      final Link link = installer.linkBin();
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
