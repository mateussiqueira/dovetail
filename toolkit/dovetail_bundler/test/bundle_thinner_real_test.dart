import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _sampleApp = Platform.environment['DOVETAIL_SAMPLE_APP'] ?? '';

late Directory root;

bool get clangMissing =>
    !Platform.isMacOS ||
    Process.runSync('which', <String>['clang']).exitCode != 0;

void compileUniversal(List<String> extra, String source, String output) {
  File(output).parent.createSync(recursive: true);
  final ProcessResult built = Process.runSync('clang', <String>[
    ...<String>['-arch', 'arm64', '-arch', 'x86_64', ...extra],
    ...<String>['-x', 'c', source, '-o', output],
  ]);
  expect(built.exitCode, 0, reason: built.stderr.toString());
}

String realUniversalBundle() {
  final String contents = p.join(root.path, 'Real.app', 'Contents');
  final File main = File(p.join(root.path, 'main.c'))
    ..writeAsStringSync('int main(void) { return 0; }\n');
  compileUniversal(<String>[], main.path, p.join(contents, 'MacOS', 'Real'));
  compileUniversal(
    <String>['-dynamiclib'],
    main.path,
    p.join(contents, 'Frameworks', 'libreal.dylib'),
  );
  File(p.join(contents, 'Info.plist')).writeAsStringSync(
    '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>\n'
    '<key>CFBundleExecutable</key><string>Real</string>\n'
    '<key>CFBundleIdentifier</key><string>com.example.real</string>\n'
    '</dict></plist>\n',
  );
  return p.dirname(contents);
}

List<String> lipoArchsOfEveryMachO(String bundle) => <String>[
  for (final FileSystemEntity entity in Directory(
    bundle,
  ).listSync(recursive: true, followLinks: false))
    if (entity is File && MachO.read(entity.path).isMachO)
      Process.runSync('lipo', <String>[
        '-archs',
        entity.path,
      ]).stdout.toString().trim(),
];

int signAdHocThenVerify(String bundle) {
  final ProcessResult signed = Process.runSync('codesign', <String>[
    ...<String>['--force', '--deep', '--sign', '-', bundle],
  ]);
  expect(signed.exitCode, 0, reason: signed.stderr.toString());
  return Process.runSync('codesign', <String>[
    ...<String>['--verify', '--deep', '--strict', bundle],
  ]).exitCode;
}

void main() {
  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_thin'));
  tearDown(() => root.deleteSync(recursive: true));

  test('a real universal bundle should come out arm64 and sign', () async {
    if (clangMissing) {
      markTestSkipped('needs macOS and clang');
      return;
    }
    final String bundle = realUniversalBundle();
    expect(lipoArchsOfEveryMachO(bundle), everyElement(contains('x86_64')));

    await const BundleThinner(
      runner: SystemProcessRunner(),
    ).thin(bundlePath: bundle, architecture: TargetArch.arm64);

    expect(lipoArchsOfEveryMachO(bundle), <String>['arm64', 'arm64']);
    expect(signAdHocThenVerify(bundle), 0);
  });

  test('the sample app should come out arm64 in every Mach-O', () async {
    if (!Directory(_sampleApp).existsSync()) {
      markTestSkipped('set DOVETAIL_SAMPLE_APP to a built .app first');
      return;
    }
    final String bundle = p.join(root.path, p.basename(_sampleApp));
    final ProcessResult copied = Process.runSync('ditto', <String>[
      _sampleApp,
      bundle,
    ]);
    expect(copied.exitCode, 0, reason: copied.stderr.toString());

    await const BundleThinner(
      runner: SystemProcessRunner(),
    ).thin(bundlePath: bundle, architecture: TargetArch.arm64);

    expect(lipoArchsOfEveryMachO(bundle), everyElement('arm64'));
    expect(signAdHocThenVerify(bundle), 0);
  });
}
