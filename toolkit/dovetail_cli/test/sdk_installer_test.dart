import 'dart:io';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/src/sdk/sdk_installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _FailingRunner implements ProcessRunner {
  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async =>
      const ProcessOutcome(exitCode: 2, stdout: '', stderr: 'tar: boom');
}

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('dovetail_sdk');
  });

  tearDown(() => home.deleteSync(recursive: true));

  group('extract', () {
    test('a tar that fails should refuse, naming the tarball', () async {
      final File tarball = File(p.join(home.path, 'sdk.tar.gz'))
        ..writeAsStringSync('not a tarball');
      final SdkInstaller installer = SdkInstaller(
        home: home.path,
        runner: _FailingRunner(),
      );

      await expectLater(
        installer.extract(tarball),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure error) => error.message,
            'message',
            contains(tarball.path),
          ),
        ),
      );
    });
  });

  group('binDir', () {
    test('an explicit binDir wins over the environment', () {
      final Directory bin = Directory.systemTemp.createTempSync('dt_bin');
      addTearDown(() => bin.deleteSync(recursive: true));
      final SdkInstaller installer = SdkInstaller(
        home: home.path,
        binDir: bin.path,
      );

      expect(installer.binDir, bin.path);
    });

    test('without a binDir, the default lands under \$HOME/.local/bin', () {
      final SdkInstaller installer = SdkInstaller(home: home.path);

      expect(
        installer.binDir,
        p.join(Platform.environment['HOME'] ?? home.path, '.local', 'bin'),
      );
    });
  });

  group('linkBin', () {
    test('the link points at the installed binary under home', () {
      final Directory bin = Directory.systemTemp.createTempSync('dt_bin');
      addTearDown(() => bin.deleteSync(recursive: true));
      final SdkInstaller installer = SdkInstaller(
        home: home.path,
        binDir: bin.path,
      );

      final Link link = installer.linkBin();

      expect(
        link.targetSync(),
        p.join(home.path, 'bin', 'dovetail'),
        reason:
            'o symlink aponta para o binário instalado, para o PATH ver '
            'a troca de versão sem re-symlink',
      );
    });
  });
}
