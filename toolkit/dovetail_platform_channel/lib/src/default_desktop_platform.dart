import 'package:dovetail_platform_channel/src/bundle/bundle_info.dart';
import 'package:dovetail_platform_channel/src/deep_link/deep_link_inbox.dart';
import 'package:dovetail_platform_channel/src/desktop_platform.dart';
import 'package:dovetail_platform_channel/src/notify/system_notifier.dart';
import 'package:dovetail_platform_channel/src/panel/panel_surface.dart';
import 'package:dovetail_platform_channel/src/open/external_opener.dart';
import 'package:dovetail_platform_channel/src/platform_capabilities.dart';
import 'package:dovetail_platform_channel/src/platform_capability.dart';
import 'package:dovetail_platform_channel/src/startup/launch_at_login.dart';
import 'package:dovetail_platform_channel/src/tray/tray_surface.dart';
import 'package:dovetail_platform_channel/src/window/window_surface.dart';

final class DefaultDesktopPlatform implements DesktopPlatform {
  const DefaultDesktopPlatform({
    required this.window,
    required this.tray,
    required this.panel,
    required this.launchAtLogin,
    required this.deepLinks,
    required this.notifier,
    required this.opener,
    required this.bundle,
    required this.capabilities,
  });

  @override
  final WindowSurface window;

  @override
  final TraySurface tray;

  @override
  final PanelSurface panel;

  @override
  final LaunchAtLogin launchAtLogin;

  @override
  final DeepLinkInbox deepLinks;

  @override
  final SystemNotifier notifier;

  @override
  final ExternalOpener opener;

  @override
  final BundleInfo bundle;

  final PlatformCapabilities capabilities;

  @override
  bool supports(PlatformCapability capability) =>
      capabilities.supports(capability);
}
