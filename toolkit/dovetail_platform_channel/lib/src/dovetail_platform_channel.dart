import 'dart:io';

import 'package:dovetail_platform_channel/src/bundle/package_info_bundle.dart';
import 'package:dovetail_platform_channel/src/deep_link/app_links_deep_link_inbox.dart';
import 'package:dovetail_platform_channel/src/deep_link/deep_link_inbox.dart';
import 'package:dovetail_platform_channel/src/deep_link/joined_deep_link_inbox.dart';
import 'package:dovetail_platform_channel/src/default_desktop_platform.dart';
import 'package:dovetail_platform_channel/src/window/window_state_keeper.dart';
import 'package:dovetail_platform_channel/src/window/window_state_store.dart';
import 'package:dovetail_platform_channel/src/window/window_surface.dart';
import 'package:dovetail_platform_channel/src/desktop_app_spec.dart';
import 'package:dovetail_platform_channel/src/desktop_platform.dart';
import 'package:dovetail_platform_channel/src/instance/single_instance.dart';
import 'package:dovetail_platform_channel/src/instance/single_instance_verdict.dart';
import 'package:dovetail_platform_channel/src/instance/socket_single_instance.dart';
import 'package:dovetail_platform_channel/src/instance/windows_single_instance.dart';
import 'package:dovetail_platform_channel/src/notify/local_notifications_notifier.dart';
import 'package:dovetail_platform_channel/src/open/url_launcher_opener.dart';
import 'package:dovetail_platform_channel/src/platform_capabilities.dart';
import 'package:dovetail_platform_channel/src/display/screen_retriever_probe.dart';
import 'package:dovetail_platform_channel/src/panel/menu_only_panel_surface.dart';
import 'package:dovetail_platform_channel/src/panel/placed_panel_surface.dart';
import 'package:dovetail_platform_channel/src/platform_capability.dart';
import 'package:dovetail_platform_channel/src/startup/executable_path.dart';
import 'package:dovetail_platform_channel/src/startup/launch_at_startup_login.dart';
import 'package:dovetail_platform_channel/src/tray/tray_manager_surface.dart';
import 'package:dovetail_platform_channel/src/window/window_manager_surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract final class DesktopPlatformChannel {
  static DesktopPlatform? _instance;

  static bool get isSupported => PlatformCapabilities.current().isDesktop;

  static DesktopPlatform get instance {
    final DesktopPlatform? ready = _instance;
    if (ready == null) {
      throw StateError(
        'DesktopPlatformChannel.ensureInitialized must run before instance.',
      );
    }
    return ready;
  }

  static SingleInstance? _guard;

  static SingleInstance? get guard => _guard;

  static Future<SingleInstanceVerdict> claimSingleInstance(
    String instanceKey, {
    List<String> arguments = const <String>[],
  }) async {
    if (!PlatformCapabilities.current().supports(
      PlatformCapability.singleInstance,
    )) {
      return SingleInstanceVerdict.unavailable;
    }

    final SingleInstance guard = _guardFor(instanceKey);
    final SingleInstanceVerdict verdict = await guard.claim(
      arguments: arguments,
    );
    if (verdict == SingleInstanceVerdict.primary) {
      _guard = guard;
    }
    return verdict;
  }

  static SingleInstance _guardFor(String instanceKey) =>
      PlatformCapabilities.current().platform == TargetPlatform.windows
      ? WindowsSingleInstance(instanceKey: instanceKey)
      : SocketSingleInstance(instanceKey: instanceKey);

  static Future<DesktopPlatform> ensureInitialized(DesktopAppSpec spec) async {
    final DesktopPlatform? ready = _instance;
    if (ready != null) {
      return ready;
    }

    WidgetsFlutterBinding.ensureInitialized();

    final WindowManagerSurface window = WindowManagerSurface();
    // Só ESTA chamada, e não as superfícies: é a primeira que toca o nativo,
    // e é a que um `flutter test` acerta — não há lado nativo num teste de
    // widget, então o `window_manager` responde MissingPluginException com um
    // texto que não diz o que fazer nem de quem é. Relançado com nome de
    // dovetail e o rastro original, no molde do RustBridge.ensureInitialized.
    // Embrulhar as superfícies também engoliria um plugin genuinamente sem
    // implementação durante trabalho nativo, que é outro problema.
    try {
      await window.attach(spec.window);
    } on MissingPluginException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError(
          'DesktopPlatformChannel.ensureInitialized: there is no native side '
          'to talk to (${error.message}). Under `flutter test` this is '
          'expected — a widget test has no window; inject a DesktopPlatform '
          'double instead of calling ensureInitialized. Running the app, it '
          'means a platform plugin has no implementation for this desktop: '
          'see docs/problemas.md, "MissingPluginException".',
        ),
        stackTrace,
      );
    }

    final ExecutablePath executable = ExecutablePath(
      platform: defaultTargetPlatform,
      resolvedExecutable: Platform.resolvedExecutable,
      environment: Platform.environment,
    );

    final LaunchAtStartupLogin launchAtLogin = LaunchAtStartupLogin()
      ..configure(
        appName: spec.displayName,
        appPath: spec.executablePath ?? executable.forLoginItem(),
        packageName: spec.applicationId,
        args: spec.launchArguments,
      );

    final LocalNotificationsNotifier notifier = LocalNotificationsNotifier(
      applicationId: spec.applicationId,
      displayName: spec.displayName,
      guid: spec.notificationGuid,
    );
    if (!await notifier.attach()) {
      stderr.writeln(
        'notifications are unavailable on this session, and the app is '
        'starting without them: ${notifier.unavailableBecause}',
      );
    }

    final PlatformCapabilities capabilities = PlatformCapabilities.current();

    final DesktopPlatform platform = DefaultDesktopPlatform(
      window: window,
      tray: TrayManagerSurface(),
      panel: capabilities.supports(PlatformCapability.anchoredPanel)
          ? PlacedPanelSurface(window: window, displays: ScreenRetrieverProbe())
          : const MenuOnlyPanelSurface(),
      launchAtLogin: launchAtLogin,
      deepLinks: _deepLinks(),
      notifier: notifier,
      opener: const UrlLauncherOpener(),
      bundle: PackageInfoBundle(),
      capabilities: capabilities,
    );

    await _rememberPlacement(spec, window);

    _instance = platform;
    return platform;
  }

  static DeepLinkInbox _deepLinks() {
    final SingleInstance? holding = _guard;
    final AppLinksDeepLinkInbox platform = AppLinksDeepLinkInbox();
    if (holding == null) {
      return platform;
    }
    return JoinedDeepLinkInbox(inbox: platform, launches: holding.launches());
  }

  static WindowStateKeeper? _keeper;

  @visibleForTesting
  static WindowStateKeeper? get placementKeeper => _keeper;

  static Future<void> _rememberPlacement(
    DesktopAppSpec spec,
    WindowSurface window,
  ) async {
    final String? directory = spec.stateDirectory;
    if (directory == null) {
      return;
    }

    final WindowStateKeeper keeper = WindowStateKeeper(
      window: window,
      store: FileWindowStateStore(directory: directory),
      displays: ScreenRetrieverProbe(),
    );
    await keeper.restore();
    keeper.watch();
    _keeper = keeper;
  }

  @visibleForTesting
  static void overrideInstance(DesktopPlatform? platform) =>
      _instance = platform;
}
