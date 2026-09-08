import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _RecordingRunner implements ProcessRunner {
  _RecordingRunner({this.exitCode = 0, this.stderr = ''});

  final int exitCode;
  final String stderr;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    String? stdin,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    return ProcessOutcome(exitCode: exitCode, stdout: '', stderr: stderr);
  }
}

VerifiedArtifact artifactNamed(String name, {String body = 'the new build'}) =>
    VerifiedArtifact.trusted(
      bytes: Uint8List.fromList(body.codeUnits),
      sourceUrl: 'https://cdn.example/$name',
      trustedComment: 'built by the release command',
    );

void main() {
  late Directory root;
  late _RecordingRunner runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('linux_installer');
    runner = _RecordingRunner();
  });

  tearDown(() => root.deleteSync(recursive: true));

  String installedAppImage() {
    final String path = p.join(root.path, 'App-x86_64.AppImage');
    File(path).writeAsStringSync('the build that is running');
    return path;
  }

  // Escreve um /proc/self/status falso para que o teste controle se o
  // processo se apresenta como root ou não, em vez de herdar o host.
  String statusWith(String uidLine) {
    final String path = p.join(root.path, 'status');
    File(path).writeAsStringSync('Name:\tdart\n$uidLine\nGid:\t0\t0\t0\t0\n');
    return path;
  }

  group('the format it was handed', () {
    test('an archive should be refused by name', () {
      expect(
        () => LinuxPackageFormat.of('app.tar.gz'),
        throwsA(
          isA<UpdateFailure>()
              .having(
                (UpdateFailure failure) => failure.message,
                'message',
                contains('app.tar.gz'),
              )
              .having(
                (UpdateFailure failure) => failure.remedy,
                'remedy',
                allOf(
                  contains('.deb'),
                  contains('.rpm'),
                  contains('.appimage'),
                ),
              ),
        ),
        reason:
            'a Linux client used to download, verify the signature and then '
            'hold an artefact nothing could apply, without a line saying so',
      );
    });

    test('the extension should be read case-insensitively', () {
      expect(
        LinuxPackageFormat.of('App-x86_64.AppImage'),
        LinuxPackageFormat.appImage,
      );
      expect(
        LinuxPackageFormat.of('client_1.0.0_amd64.DEB'),
        LinuxPackageFormat.debian,
      );
    });

    test('only the AppImage should apply without privilege', () {
      expect(LinuxPackageFormat.appImage.needsPrivilege, false);
      expect(LinuxPackageFormat.debian.needsPrivilege, true);
      expect(LinuxPackageFormat.rpm.needsPrivilege, true);
    });
  });

  group('an AppImage replacing itself', () {
    test('should end holding the new bytes and no backup', () async {
      final String path = installedAppImage();

      expect(
        await LinuxInstaller(
          runner: runner,
          appImagePath: path,
        ).install(artifactNamed('App-x86_64.AppImage')),
        InstallOutcome.installedRestartNeeded,
      );

      expect(File(path).readAsStringSync(), 'the new build');
      expect(File('$path.previous').existsSync(), false);
      expect(
        runner.calls,
        <List<String>>[
          <String>['chmod', '755', path],
        ],
        reason:
            'an AppImage that is not executable is a file the desktop refuses '
            'to launch, which reads to the user as the update having deleted '
            'the app',
      );
    });

    test('should refuse a path where nothing is installed', () async {
      await expectLater(
        LinuxInstaller(
          runner: runner,
          appImagePath: p.join(root.path, 'absent.AppImage'),
        ).install(artifactNamed('absent.AppImage')),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('APPIMAGE'),
          ),
        ),
      );
    });

    test('a leftover backup should not block the next update', () async {
      final String path = installedAppImage();
      File('$path.previous').writeAsStringSync('a build from a crashed update');

      await LinuxInstaller(
        runner: runner,
        appImagePath: path,
      ).install(artifactNamed('App-x86_64.AppImage'));

      expect(File(path).readAsStringSync(), 'the new build');
      expect(File('$path.previous').existsSync(), false);
    });

    test('a chmod that fails should say how to finish by hand', () async {
      final String path = installedAppImage();

      await expectLater(
        LinuxInstaller(
          runner: _RecordingRunner(exitCode: 1),
          appImagePath: path,
        ).install(artifactNamed('App-x86_64.AppImage')),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('chmod 755 $path'),
          ),
        ),
      );
    });
  });

  group('a package handed to the system', () {
    test('a deb should go through pkexec dpkg --install', () async {
      await LinuxInstaller(
        runner: runner,
        appImagePath: installedAppImage(),
        processStatusFile: statusWith('Uid:\t1000\t1000\t1000\t1000'),
      ).install(artifactNamed('client_1.0.0_amd64.deb'));

      expect(
        runner.calls.single.first,
        'pkexec',
        reason:
            'dpkg refuses to run without root, so a desktop process has to '
            'ask for it through pkexec instead of failing with a permission '
            'error on the first package it hands over',
      );
      expect(runner.calls.single.sublist(1, 3), <String>['dpkg', '--install']);
      expect(runner.calls.single.last, endsWith('client_1.0.0_amd64.deb'));
    });

    test(
      'an rpm should replace the package, not refuse it as present',
      () async {
        await LinuxInstaller(
          runner: runner,
          appImagePath: installedAppImage(),
          processStatusFile: statusWith('Uid:\t1000\t1000\t1000\t1000'),
        ).install(artifactNamed('client-1.0.0-1.x86_64.rpm'));

        expect(runner.calls.single.first, 'pkexec');
        expect(
          runner.calls.single.sublist(1, 4),
          <String>['rpm', '--upgrade', '--replacepkgs'],
          reason:
              'rpm -U exits 2 on a package whose version is already installed, '
              'which a re-run of a half-finished update hits every time',
        );
        expect(runner.calls.single.last, endsWith('client-1.0.0-1.x86_64.rpm'));
      },
    );

    test('the temporary package should not be left behind', () async {
      final Directory scratch = Directory(p.join(root.path, 'scratch'));

      await LinuxInstaller(
        runner: runner,
        appImagePath: installedAppImage(),
        scratchDirectory: scratch.path,
      ).install(artifactNamed('client_1.0.0_amd64.deb'));

      expect(
        scratch.existsSync(),
        false,
        reason:
            'the package is written beside nothing the user owns, and a '
            'release that leaves one behind per update fills the disk quietly',
      );
    });

    test(
      'a dismissed authorisation dialog should be named, not guessed',
      () async {
        await expectLater(
          LinuxInstaller(
            runner: _RecordingRunner(exitCode: 126),
            appImagePath: installedAppImage(),
            processStatusFile: statusWith('Uid:\t1000\t1000\t1000\t1000'),
          ).install(artifactNamed('client_1.0.0_amd64.deb')),
          throwsA(
            isA<UpdateFailure>()
                .having(
                  (UpdateFailure failure) => failure.message,
                  'message',
                  contains('126'),
                )
                .having(
                  (UpdateFailure failure) => failure.remedy,
                  'remedy',
                  contains('dismissed'),
                ),
          ),
        );
      },
    );

    test('what the package manager printed should reach the caller', () async {
      await expectLater(
        LinuxInstaller(
          runner: _RecordingRunner(
            exitCode: 1,
            stderr: 'dpkg: error: cannot access archive: Permission denied',
          ),
          appImagePath: installedAppImage(),
        ).install(artifactNamed('client_1.0.0_amd64.deb')),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('cannot access archive'),
          ),
        ),
      );
    });

    test('every line rpm printed should reach the caller', () async {
      await expectLater(
        LinuxInstaller(
          runner: _RecordingRunner(
            exitCode: 1,
            stderr:
                'error: Failed dependencies:\n'
                '\tgtk3 is needed by client-1.0.0-1.aarch64\n',
          ),
          appImagePath: installedAppImage(),
        ).install(artifactNamed('client-1.0.0-1.aarch64.rpm')),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('gtk3 is needed by'),
          ),
        ),
      );
    });

    test('an AppImage should never be routed through pkexec', () {
      expect(
        () => LinuxInstaller(
          runner: runner,
          appImagePath: installedAppImage(),
        ).argumentsFor(LinuxPackageFormat.appImage, '/tmp/App.AppImage'),
        throwsStateError,
      );
    });
  });

  group('the privilege it asks for', () {
    test('a root process should call the package manager directly', () async {
      final LinuxInstaller sut = LinuxInstaller(
        runner: runner,
        appImagePath: p.join(root.path, 'unused.AppImage'),
        scratchDirectory: p.join(root.path, 'scratch'),
        processStatusFile: statusWith('Uid:\t0\t0\t0\t0'),
      );

      await sut.install(artifactNamed('app_1.0.0_amd64.deb'));

      expect(
        runner.calls.single.first,
        'dpkg',
        reason:
            'pkexec has no authorisation agent to ask over ssh or in a '
            'container, and exits 127; root does not need one',
      );
    });

    test('an unprivileged process should go through pkexec', () async {
      final LinuxInstaller sut = LinuxInstaller(
        runner: runner,
        appImagePath: p.join(root.path, 'unused.AppImage'),
        scratchDirectory: p.join(root.path, 'scratch'),
        processStatusFile: statusWith('Uid:\t1000\t1000\t1000\t1000'),
      );

      await sut.install(artifactNamed('app_1.0.0_amd64.deb'));

      expect(runner.calls.single.first, 'pkexec');
      expect(runner.calls.single[1], 'dpkg');
    });

    test('the effective uid should decide, not the real one', () async {
      final LinuxInstaller sut = LinuxInstaller(
        runner: runner,
        appImagePath: p.join(root.path, 'unused.AppImage'),
        scratchDirectory: p.join(root.path, 'scratch'),
        processStatusFile: statusWith('Uid:\t1000\t0\t0\t0'),
      );

      expect(
        sut.alreadyPrivileged(),
        true,
        reason:
            'a setuid binary runs with a real uid that is not root and an '
            'effective uid that is, and it is the effective one that installs',
      );
    });

    test('no proc filesystem should mean no privilege assumed', () {
      final LinuxInstaller sut = LinuxInstaller(
        runner: runner,
        appImagePath: p.join(root.path, 'unused.AppImage'),
        processStatusFile: p.join(root.path, 'there-is-no-proc-here'),
      );

      expect(sut.alreadyPrivileged(), false);
    });
  });
}
