export 'package:dovetail_platform_channel/src/appearance/system_appearance.dart';
export 'package:dovetail_platform_channel/src/appearance/system_appearance_probe.dart';
export 'package:dovetail_platform_channel/src/bundle/bundle_info.dart';
export 'package:dovetail_platform_channel/src/deep_link/deep_link_inbox.dart';
export 'package:dovetail_platform_channel/src/deep_link/joined_deep_link_inbox.dart';
export 'package:dovetail_platform_channel/src/deep_link/launch_arguments.dart';
export 'package:dovetail_platform_channel/src/desktop_app_spec.dart';
export 'package:dovetail_platform_channel/src/desktop_platform.dart';
export 'package:dovetail_platform_channel/src/dovetail_platform_channel.dart';
export 'package:dovetail_platform_channel/src/display/display_probe.dart';
// `ScreenRetrieverProbe` deixou de ser publico. E a IMPLEMENTACAO de
// `DisplayProbe` (esse continua exportado, e e o tipo que um consumidor
// nomeia), e a assinatura dela carrega `ScreenRetriever?` e `Display` — tipos
// do plugin screen_retriever, que nenhum consumidor declara. Quem importava so
// o barril do dovetail e tocava nela recebia "Undefined class 'Display'".
// Ninguem fora deste pacote a usava: zero ocorrencias em product/, nos
// templates e nos outros pacotes do toolkit.
export 'package:dovetail_platform_channel/src/instance/forwarded_launch.dart';
export 'package:dovetail_platform_channel/src/instance/single_instance.dart';
export 'package:dovetail_platform_channel/src/instance/single_instance_verdict.dart';
export 'package:dovetail_platform_channel/src/instance/socket_single_instance.dart';
export 'package:dovetail_platform_channel/src/instance/windows_single_instance.dart';
export 'package:dovetail_platform_channel/src/notify/notifications_unavailable.dart';
export 'package:dovetail_platform_channel/src/notify/session_bus.dart';
export 'package:dovetail_platform_channel/src/notify/system_notice.dart';
export 'package:dovetail_platform_channel/src/notify/system_notifier.dart';
export 'package:dovetail_platform_channel/src/open/external_opener.dart';
export 'package:dovetail_platform_channel/src/panel/menu_only_panel_surface.dart';
export 'package:dovetail_platform_channel/src/panel/panel_geometry.dart';
export 'package:dovetail_platform_channel/src/panel/panel_spec.dart';
export 'package:dovetail_platform_channel/src/panel/panel_surface.dart';
export 'package:dovetail_platform_channel/src/panel/placed_panel_surface.dart';
export 'package:dovetail_platform_channel/src/platform_capabilities.dart';
export 'package:dovetail_platform_channel/src/platform_capability.dart';
export 'package:dovetail_platform_channel/src/startup/executable_path.dart';
export 'package:dovetail_platform_channel/src/startup/launch_at_login.dart';
export 'package:dovetail_platform_channel/src/tray/tray_entry.dart';
export 'package:dovetail_platform_channel/src/tray/tray_gesture.dart';
export 'package:dovetail_platform_channel/src/tray/tray_icon_asset.dart';
export 'package:dovetail_platform_channel/src/tray/tray_surface.dart';
export 'package:dovetail_platform_channel/src/window/placement_guard.dart';
export 'package:dovetail_platform_channel/src/window/window_frame_state.dart';
export 'package:dovetail_platform_channel/src/window/window_placement.dart';
export 'package:dovetail_platform_channel/src/window/window_spec.dart';
export 'package:dovetail_platform_channel/src/window/window_state_keeper.dart';
export 'package:dovetail_platform_channel/src/window/window_state_store.dart';
export 'package:dovetail_platform_channel/src/window/window_surface.dart';
