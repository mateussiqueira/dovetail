import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

final String _realApp = inRepo(<String>[
  'product',
  'vpn_desktop',
  'build',
  'macos',
  'Build',
  'Products',
  'Debug',
  'vpn_desktop.app',
]);

void main() {
  late Directory root;
  late CommandRunner<int> runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_bundlearch');
    runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(BundleCommand());
  });

  tearDown(() => root.deleteSync(recursive: true));

  List<String> argumentsFor(
    String target,
    String appDir,
    List<String> arches,
  ) => <String>[
    'bundle',
    '--target',
    target,
    '--product-name',
    'Example',
    '--manufacturer',
    'Example Ltda',
    '--identifier',
    'io.example.client',
    '--version',
    '2.1.0',
    '--main-binary',
    'client',
    '--app-dir',
    appDir,
    '--out-dir',
    p.join(root.path, 'out'),
    for (final String arch in arches) ...<String>['--arch', arch],
  ];

  test('a thin app asked for universal should be refused', () async {
    if (!Directory(_realApp).existsSync()) {
      markTestSkipped('build vpn_desktop for macOS first');
      return;
    }

    await expectLater(
      runner.run(argumentsFor('macos', _realApp, <String>['x86_64', 'arm64'])),
      throwsA(
        isA<BundleFailure>().having(
          (BundleFailure failure) => failure.message,
          'message',
          contains('does not carry'),
        ),
      ),
      reason:
          'BundleArchitectures.enforce existed and the CLI never called it, so '
          'hdiutil wrapped whatever it was handed',
    );
    expect(Directory(p.join(root.path, 'out')).existsSync(), false);
  });

  test('the architecture asked for should reach the file name', () async {
    if (!Directory(_realApp).existsSync()) {
      markTestSkipped('build vpn_desktop for macOS first');
      return;
    }

    await runner.run(argumentsFor('macos', _realApp, <String>['arm64']));

    expect(
      Directory(
        p.join(root.path, 'out'),
      ).listSync().map((FileSystemEntity entity) => p.basename(entity.path)),
      contains('client_2.1.0_arm64.dmg'),
      reason:
          'without the suffix, two architectures built into one out-dir '
          'overwrite each other and the second wins silently',
    );
  });

  test('two architectures should be refused on windows', () async {
    final String app = p.join(root.path, 'stage');
    Directory(app).createSync();
    File(p.join(app, 'client.exe')).writeAsStringSync('x');

    await expectLater(
      runner.run(<String>[
        ...argumentsFor('windows', app, <String>['x86_64', 'arm64']),
        '--windows-format',
        'msi',
        '--upgrade-code',
        '5C9E1E0A-3B2D-4A11-9F0E-7D6C5B4A3928',
      ]),
      throwsA(
        isA<UsageException>().having(
          (UsageException error) => error.usage,
          'usage',
          contains('once per architecture'),
        ),
      ),
    );
  });

  test('two architectures should be refused on linux', () async {
    final String app = p.join(root.path, 'stage');
    Directory(app).createSync();
    File(p.join(app, 'client')).writeAsStringSync('x');

    await expectLater(
      runner.run(argumentsFor('linux', app, <String>['x86_64', 'arm64'])),
      throwsA(isA<UsageException>()),
    );
  });

  test('x86_64 should still be the default when no arch is given', () async {
    final String app = p.join(root.path, 'stage');
    Directory(app).createSync();
    File(p.join(app, 'client')).writeAsStringSync('x');

    final List<String> withoutArch = <String>[
      'bundle',
      '--target',
      'linux',
      '--product-name',
      'Example',
      '--manufacturer',
      'Example Ltda',
      '--identifier',
      'io.example.client',
      '--version',
      '2.1.0',
      '--main-binary',
      'client',
      '--app-dir',
      app,
      '--out-dir',
      p.join(root.path, 'out'),
    ];

    try {
      await runner.run(withoutArch);
    } on BundleFailure catch (failure) {
      expect(
        '${failure.message} ${failure.remedy}',
        contains('x86_64'),
        reason:
            'this machine only has an aarch64 rpm arch table, so the rpm step '
            'fails naming the architecture the CLI chose — which is the proof '
            'of the default',
      );
    }

    expect(
      Directory(
        p.join(root.path, 'out'),
      ).listSync().map((FileSystemEntity entity) => p.basename(entity.path)),
      contains('client_2.1.0_amd64.deb'),
      reason: 'the deb is built before the rpm, and amd64 is x86_64 in Debian',
    );
  });
}
