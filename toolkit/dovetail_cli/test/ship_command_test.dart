import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/stdout_capture.dart';

/// The ship command reads `dovetail.yaml` from the working directory — it has
/// no `--root`, so `ConfigLocator.findFile()` starts at `Directory.current`.
/// Overriding `getCurrentDirectory` in a zone keeps that pointing at the
/// fixture without moving the process-wide cwd, which every other suite in
/// the run shares.
const String _config = '''
identifier: com.example.demo
name: Demo Client
manufacturer: Example Ltda
targets: [darwin-aarch64, windows-x86_64, linux-x86_64]
''';

void main() {
  final (
    String host,
    String target,
    String binaryArtifact,
  ) = switch (Platform.operatingSystem) {
    'macos' => ('macos', 'darwin-aarch64', 'client_app.app'),
    'windows' => ('windows', 'windows-x86_64', 'client_app_4.2.0_x64.msi'),
    'linux' => ('linux', 'linux-x86_64', 'client_app_4.2.0_amd64.deb'),
    _ => throw UnsupportedError(
      'ship fixture host: ${Platform.operatingSystem}',
    ),
  };

  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_ship_cmd'));
  tearDown(() => root.deleteSync(recursive: true));

  Directory project() {
    final Directory dir = Directory(p.join(root.path, 'project'))
      ..createSync(recursive: true);
    File(p.join(dir.path, ConfigLocator.fileName)).writeAsStringSync(_config);
    return dir;
  }

  Future<int?> shipIn(String cwd, List<String> args, CapturedStdout out) =>
      IOOverrides.runZoned(
        () => (CommandRunner<int>(
          'dovetail',
          'test',
        )..addCommand(ShipCommand())).run(<String>['ship', ...args]),
        stdout: () => out,
        getCurrentDirectory: () => Directory(cwd),
        setCurrentDirectory: (_) {},
      );

  test('no config anywhere should refuse, and say what to run', () async {
    await expectLater(
      shipIn(root.path, <String>['--dry-run'], CapturedStdout()),
      throwsA(
        isA<UsageException>().having(
          (UsageException error) => error.message,
          'message',
          contains('no dovetail.yaml'),
        ),
      ),
      reason:
          'ship reads everything from the config; without one there is '
          'nothing to read',
    );
  });

  test('--dry-run should print the plan and run none of it', () async {
    final CapturedStdout out = CapturedStdout();
    final int? code = await shipIn(project().path, <String>[
      '--dry-run',
      '--version',
      '4.2.0',
      '--binary',
      'demo_app',
    ], out);

    final String text = out.text.toString();
    expect(code, 0);
    expect(text, contains('→ build $host'));
    expect(text, contains('→ sign $target'));
    expect(text, contains('→ bundle $target'));
    expect(text, contains('dovetail build --target $host'));
    expect(
      text,
      contains(
        'dovetail sign --target $host '
        '${Platform.isMacOS ? '--bundle' : '--file'}',
      ),
      reason: 'the plan is data, printed before any tool runs',
    );
  });

  test('--no-build should drop only the build step', () async {
    final CapturedStdout out = CapturedStdout();
    final int? code = await shipIn(project().path, <String>[
      '--dry-run',
      '--no-build',
      '--version',
      '4.2.0',
      '--binary',
      'demo_app',
    ], out);

    final String text = out.text.toString();
    expect(code, 0);
    expect(text, isNot(contains('build $host')));
    expect(text, contains('→ sign $target'));
    expect(text, contains('→ bundle $target'));
    expect(
      text,
      isNot(contains('dovetail build')),
      reason: '--no-build reuses the last build, so no build step is planned',
    );
  });

  test(
    '--binary should name the artefacts the plan hands to the toolchain',
    () async {
      final CapturedStdout out = CapturedStdout();
      final int? code = await shipIn(project().path, <String>[
        '--dry-run',
        '--version',
        '4.2.0',
        '--binary',
        'client_app',
      ], out);

      expect(code, 0);
      expect(out.text.toString(), contains('--main-binary client_app'));
      expect(
        out.text.toString(),
        contains(binaryArtifact),
        reason: 'the binary name is what the sign step points the bundler at',
      );
    },
  );
}
