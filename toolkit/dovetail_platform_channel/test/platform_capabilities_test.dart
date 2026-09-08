import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supports should answer false for every capability off desktop', () {
    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    ]) {
      final sut = PlatformCapabilities(platform);

      for (final PlatformCapability capability in PlatformCapability.values) {
        expect(
          sut.supports(capability),
          false,
          reason: '${platform.name} $capability',
        );
      }
    }
  });

  test(
    'supports should answer true for the tray tooltip on windows and macOS',
    () {
      for (final TargetPlatform platform in <TargetPlatform>[
        TargetPlatform.windows,
        TargetPlatform.macOS,
      ]) {
        final sut = PlatformCapabilities(platform);

        expect(
          sut.supports(PlatformCapability.trayTooltip),
          true,
          reason: platform.name,
        );
      }
    },
  );

  test('supports should answer false for the tray tooltip on linux', () {
    const sut = PlatformCapabilities(TargetPlatform.linux);

    expect(sut.supports(PlatformCapability.trayTooltip), false);
    expect(sut.supports(PlatformCapability.trayIcon), true);
    expect(sut.supports(PlatformCapability.trayMenu), true);
  });

  test('supports should answer true for single instance on every desktop', () {
    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      final sut = PlatformCapabilities(platform);

      expect(
        sut.supports(PlatformCapability.singleInstance),
        true,
        reason:
            'macOS and Linux answer through a unix domain socket, which '
            'dart:io has no Windows equivalent for; Windows answers through '
            'the guard in the plugin. A guard that fails to load reports an '
            'unavailable verdict, which is not the same as the platform '
            'having no guard at all: ${platform.name}',
      );
    }
  });

  test('isDesktop should follow the platform', () {
    expect(const PlatformCapabilities(TargetPlatform.linux).isDesktop, true);
    expect(const PlatformCapabilities(TargetPlatform.android).isDesktop, false);
  });

  test('current should read the ambient platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(PlatformCapabilities.current().platform, TargetPlatform.linux);
  });
}
