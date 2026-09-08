import 'dart:io';

import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const List<String> _appleTargets = <String>[
  'x86_64-apple-darwin',
  'aarch64-apple-darwin',
];

bool _present(String tool) =>
    Process.runSync('which', <String>[tool]).exitCode == 0;

String? _missingPrerequisite() {
  if (!Platform.isMacOS) {
    return 'a universal Mach-O and codesign only exist on macOS';
  }
  for (final String tool in <String>['rustc', 'lipo', 'codesign']) {
    if (!_present(tool)) {
      return '$tool is not installed';
    }
  }
  final Set<String> installed = Process.runSync('rustup', <String>[
    'target',
    'list',
    '--installed',
  ]).stdout.toString().split('\n').map((String l) => l.trim()).toSet();
  for (final String target in _appleTargets) {
    if (!installed.contains(target)) {
      return 'rustup target add $target';
    }
  }
  return null;
}

String _buildUniversalApp(Directory root) {
  final File source = File(p.join(root.path, 'probe.rs'))
    ..writeAsStringSync('fn main() {\n    println!("probe");\n}\n');

  final List<String> slices = <String>[];
  for (final String target in _appleTargets) {
    final String output = p.join(root.path, 'probe-$target');
    final ProcessResult built = Process.runSync('rustc', <String>[
      '--edition',
      '2021',
      '-O',
      '--target',
      target,
      '-o',
      output,
      source.path,
    ]);
    if (built.exitCode != 0) {
      throw StateError('rustc failed for $target: ${built.stderr}');
    }
    slices.add(output);
  }

  final String fat = p.join(root.path, 'probe-universal');
  final ProcessResult merged = Process.runSync('lipo', <String>[
    '-create',
    ...slices,
    '-output',
    fat,
  ]);
  if (merged.exitCode != 0) {
    throw StateError('lipo failed: ${merged.stderr}');
  }

  final String app = p.join(root.path, 'Probe.app');
  final String framework = p.join(
    app,
    'Contents',
    'Frameworks',
    'Helper.framework',
  );
  Directory(p.join(app, 'Contents', 'MacOS')).createSync(recursive: true);
  Directory(
    p.join(framework, 'Versions', 'A', 'Resources'),
  ).createSync(recursive: true);

  File(fat).copySync(p.join(app, 'Contents', 'MacOS', 'Probe'));
  File(fat).copySync(p.join(framework, 'Versions', 'A', 'Helper'));
  Link(p.join(framework, 'Versions', 'Current')).createSync('A');
  Link(p.join(framework, 'Helper')).createSync('Versions/Current/Helper');
  Link(p.join(framework, 'Resources')).createSync('Versions/Current/Resources');

  File(p.join(app, 'Contents', 'Info.plist')).writeAsStringSync(
    _plist(identifier: 'io.example.probe', executable: 'Probe', type: 'APPL'),
  );
  File(
    p.join(framework, 'Versions', 'A', 'Resources', 'Info.plist'),
  ).writeAsStringSync(
    _plist(
      identifier: 'io.example.probe.helper',
      executable: 'Helper',
      type: 'FMWK',
    ),
  );

  return app;
}

String _plist({
  required String identifier,
  required String executable,
  required String type,
}) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n<dict>\n'
    '  <key>CFBundleExecutable</key><string>$executable</string>\n'
    '  <key>CFBundleIdentifier</key><string>$identifier</string>\n'
    '  <key>CFBundleName</key><string>$executable</string>\n'
    '  <key>CFBundlePackageType</key><string>$type</string>\n'
    '  <key>CFBundleShortVersionString</key><string>1.0.0</string>\n'
    '</dict>\n</plist>\n';

Set<String> _archsOf(String path) =>
    Process.runSync('lipo', <String>['-archs', path]).stdout
        .toString()
        .trim()
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty)
        .toSet();

void main() {
  final String? blocked = _missingPrerequisite();
  late Directory root;
  late String app;

  setUp(() {
    if (blocked != null) {
      return;
    }
    root = Directory.systemTemp.createTempSync('dovetail_fatsign');
    app = _buildUniversalApp(root);
  });

  tearDown(() {
    if (blocked == null) {
      root.deleteSync(recursive: true);
    }
  });

  Future<List<SignTarget>> signIt() =>
      const MacosSigner(runner: SystemProcessRunner()).sign(
        request: MacosSigningRequest(bundlePath: app, identity: '-'),
        contents: Directory(app)
            .listSync(recursive: true, followLinks: false)
            .map((FileSystemEntity entity) => entity.path)
            .toList(),
      );

  test('the fixture should be a genuinely universal bundle', () {
    if (blocked != null) {
      markTestSkipped(blocked);
      return;
    }

    expect(_archsOf(p.join(app, 'Contents', 'MacOS', 'Probe')), <String>{
      'x86_64',
      'arm64',
    });
  });

  test('codesign --verify should accept each slice on its own', () async {
    if (blocked != null) {
      markTestSkipped(blocked);
      return;
    }

    await signIt();

    for (final String arch in <String>['x86_64', 'arm64']) {
      final ProcessResult verified = Process.runSync('codesign', <String>[
        '--verify',
        '--deep',
        '--strict',
        '--arch',
        arch,
        app,
      ]);
      expect(verified.exitCode, 0, reason: 'arch $arch: ${verified.stderr}');
    }
  });

  test('both slices should carry the same bundle identifier', () async {
    if (blocked != null) {
      markTestSkipped(blocked);
      return;
    }

    await signIt();

    final Set<String> identifiers = <String>{};
    for (final String arch in <String>['x86_64', 'arm64']) {
      final String printed = Process.runSync('codesign', <String>[
        '-dv',
        '--arch',
        arch,
        app,
      ]).stderr.toString();
      identifiers.add(
        printed
            .split('\n')
            .firstWhere((String line) => line.startsWith('Identifier='))
            .trim(),
      );
    }
    expect(identifiers, <String>{'Identifier=io.example.probe'});
  });

  test('the nested framework should be sealed before the bundle', () async {
    if (blocked != null) {
      markTestSkipped(blocked);
      return;
    }

    final List<SignTarget> order = await signIt();
    final int framework = order.indexWhere(
      (SignTarget target) => target.path.endsWith('Helper.framework'),
    );
    final int bundle = order.indexWhere(
      (SignTarget target) => target.path == app,
    );

    expect(framework, isNonNegative);
    expect(
      framework,
      lessThan(bundle),
      reason:
          'signing the bundle first seals a hash of code that is about to '
          'change, and codesign --deep --strict then rejects it',
    );
  });

  test('merging after signing should break the seal', () async {
    if (blocked != null) {
      markTestSkipped(blocked);
      return;
    }

    await signIt();
    expect(
      Process.runSync('codesign', <String>[
        '--verify',
        '--deep',
        '--strict',
        app,
      ]).exitCode,
      0,
    );

    final String thin = p.join(root.path, 'probe-aarch64-apple-darwin');
    File(thin).copySync(p.join(app, 'Contents', 'MacOS', 'Probe'));

    expect(
      Process.runSync('codesign', <String>[
        '--verify',
        '--deep',
        '--strict',
        app,
      ]).exitCode,
      isNot(0),
      reason:
          'lipo must run before the signer, never after: the bundle seal '
          'covers the bytes of every Mach-O it contains',
    );
  });
}
