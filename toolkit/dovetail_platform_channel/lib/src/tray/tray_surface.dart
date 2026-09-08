import 'package:dovetail_platform_channel/src/tray/tray_entry.dart';
import 'package:dovetail_platform_channel/src/tray/tray_gesture.dart';
import 'package:dovetail_platform_channel/src/tray/tray_icon_asset.dart';

abstract interface class TraySurface {
  Future<void> attach({required TrayIconAsset icon, List<TrayEntry> menu});

  Future<void> setIcon(TrayIconAsset icon);
  Future<void> setTooltip(String text);
  Future<void> setMenu(List<TrayEntry> entries);
  Future<void> detach();

  Stream<String> commands();
  Stream<TrayGesture> gestures();
}
