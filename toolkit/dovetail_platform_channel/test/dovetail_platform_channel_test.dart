import 'package:flutter/foundation.dart';
import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => DesktopPlatformChannel.overrideInstance(null));

  test('instance should refuse to answer before initialization', () {
    expect(() => DesktopPlatformChannel.instance, throwsStateError);
  });

  test('claimSingleInstance should answer primary for a fresh key', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(
      await DesktopPlatformChannel.claimSingleInstance(
        'com.example.test.fresh',
      ),
      SingleInstanceVerdict.primary,
    );

    expect(
      DesktopPlatformChannel.guard,
      isNotNull,
      reason:
          'the verdict is only worth reading if a guard is holding it, and '
          'without the override this test answered primary while holding '
          'nothing at all',
    );
    await DesktopPlatformChannel.guard?.release();
  });

  test('claimSingleInstance on windows should answer unavailable', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final SingleInstance? before = DesktopPlatformChannel.guard;

    expect(
      await DesktopPlatformChannel.claimSingleInstance('com.example.test.win'),
      SingleInstanceVerdict.unavailable,
    );
    expect(
      DesktopPlatformChannel.guard,
      same(before),
      reason: 'the path that cannot guard must not install a guard either',
    );
  });
}
