import 'dart:io';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const ProcessRunner _runner = SystemProcessRunner();

UpdateInstaller resolveFor(String os, {String path = '/opt/demo/demo'}) =>
    InstallerForHost.resolve(
      runner: _runner,
      installedPath: path,
      launcher: const SystemProcessRunner(),
      operatingSystem: os,
    );

void main() {
  group('the installer each host needs', () {
    test('macos should get the bundle replacer', () {
      expect(resolveFor('macos'), isA<MacosInstaller>());
    });

    test('windows should get the one that runs an installer', () {
      expect(resolveFor('windows'), isA<WindowsInstaller>());
    });

    test('linux should get the one that knows three package formats', () {
      expect(resolveFor('linux'), isA<LinuxInstaller>());
    });

    test('a host with no installer should refuse, not return null', () {
      expect(
        () => resolveFor('fuchsia'),
        throwsA(
          isA<UpdateFailure>()
              .having(
                (UpdateFailure failure) => failure.message,
                'message',
                contains('fuchsia'),
              )
              .having(
                (UpdateFailure failure) => failure.remedy,
                'remedy',
                contains('done nothing with it'),
              ),
        ),
        reason:
            'a client that verifies an update it cannot apply has already told '
            'the user a new version is ready',
      );
    });
  });

  group('the bundle a macOS path belongs to', () {
    test('the executable inside a bundle should resolve to the bundle', () {
      final MacosInstaller installer =
          resolveFor(
                'macos',
                path: '/Applications/Demo.app/Contents/MacOS/demo',
              )
              as MacosInstaller;

      expect(
        installer.bundlePath,
        '/Applications/Demo.app',
        reason:
            'Platform.resolvedExecutable points inside the bundle, and '
            'replacing that one file leaves a bundle whose seal no longer '
            'matches its contents',
      );
    });

    test('a bundle path should be left as it is', () {
      final MacosInstaller installer =
          resolveFor('macos', path: '/Applications/Demo.app') as MacosInstaller;

      expect(installer.bundlePath, '/Applications/Demo.app');
    });

    test('a path in no bundle at all should be kept, not walked to root', () {
      final MacosInstaller installer =
          resolveFor('macos', path: '/usr/local/bin/demo') as MacosInstaller;

      expect(installer.bundlePath, '/usr/local/bin/demo');
    });

    test('a nested bundle should resolve to the innermost one', () {
      final MacosInstaller installer =
          resolveFor(
                'macos',
                path:
                    '/Applications/Outer.app/Contents/Helpers/'
                    'Inner.app/Contents/MacOS/inner',
              )
              as MacosInstaller;

      expect(
        installer.bundlePath,
        p.join('/Applications/Outer.app/Contents/Helpers', 'Inner.app'),
      );
    });
  });

  group('the path the host reports', () {
    test('a linux host without APPIMAGE should say what is missing', () {
      if (!Platform.isLinux) {
        markTestSkipped('the AppImage rule only applies on Linux');
        return;
      }

      expect(
        InstallerForHost.installedPathForHost,
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('APPIMAGE'),
          ),
        ),
      );
    });

    test('elsewhere it should be the running executable', () {
      if (Platform.isLinux) {
        markTestSkipped('Linux reads APPIMAGE instead');
        return;
      }

      expect(
        InstallerForHost.installedPathForHost(),
        Platform.resolvedExecutable,
      );
    });
  });
}
