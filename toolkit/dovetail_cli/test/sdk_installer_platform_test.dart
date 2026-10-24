import 'dart:io';

import 'package:dovetail_cli/src/sdk/sdk_installer.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _RecordingRunner implements ProcessRunner {
  late String executable;
  late List<String> arguments;

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    return const ProcessOutcome(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  final Map<String, String> environment = <String, String>{
    'USERPROFILE': r'C:\Users\Windows User',
    'HOME': '/shell/home',
  };

  for (final p.Style style in <p.Style>[p.Style.windows, p.Style.posix]) {
    final p.Context context = p.Context(style: style);
    test('$style SDK bin follows the platform user home', () {
      expect(
        SdkInstaller(
          home: 'sdk',
          context: context,
          environment: environment,
        ).binDir,
        style == p.Style.windows
            ? r'C:\Users\Windows User\.local\bin'
            : '/shell/home/.local/bin',
      );
    });

    test(
      '$style SDK bin override preserves explicit and environment precedence',
      () {
        final Map<String, String> env = <String, String>{
          ...environment,
          'DOVETAIL_BIN_DIR': 'env-bin',
        };
        expect(
          SdkInstaller(home: 'sdk', context: context, environment: env).binDir,
          'env-bin',
        );
        expect(
          SdkInstaller(
            home: 'sdk',
            binDir: 'explicit-bin',
            context: context,
            environment: env,
          ).binDir,
          'explicit-bin',
        );
      },
    );

    test(
      '$style extraction uses its archive flag and installed binary name',
      () async {
        final Directory root = Directory.systemTemp.createTempSync(
          'dovetail_sdk_extract',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final _RecordingRunner runner = _RecordingRunner();
        final SdkInstaller installer = SdkInstaller(
          home: root.path,
          context: context,
          environment: environment,
          runner: runner,
        );
        final File archive = File(p.join(root.path, 'release.zip'));
        final String installed = await installer.extract(archive);
        expect(runner.executable, 'tar');
        expect(runner.arguments, <String>[
          style == p.Style.windows ? '-xf' : '-xzf',
          archive.path,
          '-C',
          root.path,
        ]);
        expect(
          installed,
          context.join(
            root.path,
            'bin',
            style == p.Style.windows ? 'dovetail.exe' : 'dovetail',
          ),
        );
      },
    );
  }
}
