import 'package:dovetail_platform_channel/src/bundle/bundle_info.dart';
import 'package:dovetail_platform_channel/src/deep_link/deep_link_inbox.dart';
import 'package:dovetail_platform_channel/src/notify/system_notifier.dart';
import 'package:dovetail_platform_channel/src/panel/panel_surface.dart';
import 'package:dovetail_platform_channel/src/open/external_opener.dart';
import 'package:dovetail_platform_channel/src/platform_capability.dart';
import 'package:dovetail_platform_channel/src/startup/launch_at_login.dart';
import 'package:dovetail_platform_channel/src/tray/tray_surface.dart';
import 'package:dovetail_platform_channel/src/window/window_surface.dart';

abstract interface class DesktopPlatform {
  WindowSurface get window;
  TraySurface get tray;
  PanelSurface get panel;
  LaunchAtLogin get launchAtLogin;
  DeepLinkInbox get deepLinks;
  SystemNotifier get notifier;
  ExternalOpener get opener;
  BundleInfo get bundle;

  bool supports(PlatformCapability capability);
}
