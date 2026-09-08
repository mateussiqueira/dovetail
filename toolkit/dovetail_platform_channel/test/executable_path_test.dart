import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'forLoginItem should return the app bundle on macOS, not the binary',
    () {
      const sut = ExecutablePath(
        platform: TargetPlatform.macOS,
        resolvedExecutable: '/Applications/Example.app/Contents/MacOS/Example',
      );

      expect(sut.forLoginItem(), '/Applications/Example.app');
    },
  );

  test('forLoginItem should survive a bundle nested in another bundle', () {
    const sut = ExecutablePath(
      platform: TargetPlatform.macOS,
      resolvedExecutable:
          '/Applications/Outer.app/Contents/Helpers/Inner.app/Contents/MacOS/Inner',
    );

    expect(sut.forLoginItem(), '/Applications/Outer.app');
  });

  test(
    'forLoginItem should fall back to the executable with no bundle on macOS',
    () {
      const sut = ExecutablePath(
        platform: TargetPlatform.macOS,
        resolvedExecutable: '/usr/local/bin/example',
      );

      expect(sut.forLoginItem(), '/usr/local/bin/example');
    },
  );

  test('forLoginItem should prefer the AppImage path on linux', () {
    const sut = ExecutablePath(
      platform: TargetPlatform.linux,
      resolvedExecutable: '/tmp/.mount_Exampl3xYz/usr/bin/example',
      environment: <String, String>{'APPIMAGE': '/home/user/Example.AppImage'},
    );

    expect(sut.forLoginItem(), '/home/user/Example.AppImage');
  });

  test(
    'forLoginItem should use the executable on linux outside an AppImage',
    () {
      const sut = ExecutablePath(
        platform: TargetPlatform.linux,
        resolvedExecutable: '/usr/bin/example',
      );

      expect(sut.forLoginItem(), '/usr/bin/example');
    },
  );

  test('forLoginItem should ignore an empty AppImage variable', () {
    const sut = ExecutablePath(
      platform: TargetPlatform.linux,
      resolvedExecutable: '/usr/bin/example',
      environment: <String, String>{'APPIMAGE': ''},
    );

    expect(sut.forLoginItem(), '/usr/bin/example');
  });

  test('forLoginItem should return the executable untouched on windows', () {
    const sut = ExecutablePath(
      platform: TargetPlatform.windows,
      resolvedExecutable: r'C:\Program Files\Example\example.exe',
      environment: <String, String>{'APPIMAGE': '/should/be/ignored'},
    );

    expect(sut.forLoginItem(), r'C:\Program Files\Example\example.exe');
  });
}
