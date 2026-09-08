import 'package:flutter/foundation.dart';
import 'package:dovetail_platform_channel/src/platform_capability.dart';

const Set<TargetPlatform> _desktop = <TargetPlatform>{
  TargetPlatform.windows,
  TargetPlatform.macOS,
  TargetPlatform.linux,
};

final class PlatformCapabilities {
  const PlatformCapabilities(this.platform);

  factory PlatformCapabilities.current() =>
      PlatformCapabilities(defaultTargetPlatform);

  final TargetPlatform platform;

  bool get isDesktop => _desktop.contains(platform);

  bool supports(PlatformCapability capability) {
    if (!isDesktop) {
      return false;
    }
    return switch (capability) {
      PlatformCapability.trayTooltip => platform != TargetPlatform.linux,
      PlatformCapability.anchoredPanel => platform != TargetPlatform.linux,
      _ => true,
    };
  }
}
