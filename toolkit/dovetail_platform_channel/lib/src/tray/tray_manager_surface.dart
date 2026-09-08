import 'dart:async';

import 'package:dovetail_platform_channel/src/platform_capabilities.dart';
import 'package:dovetail_platform_channel/src/platform_capability.dart';
import 'package:dovetail_platform_channel/src/tray/tray_entry.dart';
import 'package:dovetail_platform_channel/src/tray/tray_gesture.dart';
import 'package:dovetail_platform_channel/src/tray/tray_icon_asset.dart';
import 'package:dovetail_platform_channel/src/tray/tray_surface.dart';
import 'package:tray_manager/tray_manager.dart';

const String _tooltipEntryId = 'dovetail_platform_channel.tray.tooltip';

final class TrayManagerSurface with TrayListener implements TraySurface {
  TrayManagerSurface({TrayManager? manager, PlatformCapabilities? capabilities})
    : _manager = manager ?? trayManager,
      _capabilities = capabilities ?? PlatformCapabilities.current();

  final TrayManager _manager;
  final PlatformCapabilities _capabilities;

  final StreamController<String> _commands =
      StreamController<String>.broadcast();
  final StreamController<TrayGesture> _gestures =
      StreamController<TrayGesture>.broadcast();

  List<TrayEntry> _menu = const <TrayEntry>[];
  String? _tooltip;
  bool _attached = false;

  bool get supportsTooltip =>
      _capabilities.supports(PlatformCapability.trayTooltip);

  @override
  Future<void> attach({
    required TrayIconAsset icon,
    List<TrayEntry> menu = const <TrayEntry>[],
  }) async {
    if (_attached) {
      return;
    }
    _manager.addListener(this);
    _attached = true;
    await _manager.setIcon(icon.path);
    await setMenu(menu);
  }

  @override
  Future<void> detach() async {
    if (!_attached) {
      return;
    }
    _manager.removeListener(this);
    _attached = false;
    await _manager.destroy();
  }

  Future<void> dispose() async {
    await detach();
    await _commands.close();
    await _gestures.close();
  }

  @override
  Future<void> setIcon(TrayIconAsset icon) => _manager.setIcon(icon.path);

  @override
  Future<void> setTooltip(String text) async {
    _tooltip = text;
    if (supportsTooltip) {
      await _manager.setToolTip(text);
      return;
    }
    await _applyMenu();
  }

  @override
  Future<void> setMenu(List<TrayEntry> entries) async {
    _menu = entries;
    await _applyMenu();
  }

  @override
  Stream<String> commands() => _commands.stream;

  @override
  Stream<TrayGesture> gestures() => _gestures.stream;

  Future<void> _applyMenu() =>
      _manager.setContextMenu(Menu(items: _menuItems()));

  List<MenuItem> _menuItems() {
    final List<MenuItem> items = <MenuItem>[];
    final String? tooltip = _tooltip;

    if (!supportsTooltip && tooltip != null && tooltip.isNotEmpty) {
      items.add(MenuItem(key: _tooltipEntryId, label: tooltip, disabled: true));
      items.add(MenuItem.separator());
    }

    items.addAll(_menu.map(_toMenuItem));
    return items;
  }

  MenuItem _toMenuItem(TrayEntry entry) => switch (entry) {
    TraySeparator() => MenuItem.separator(),
    TrayCommand(
      id: final String id,
      label: final String label,
      enabled: final bool enabled,
      checked: final bool? checked,
    ) =>
      checked == null
          ? MenuItem(key: id, label: label, disabled: !enabled)
          : MenuItem.checkbox(
              key: id,
              label: label,
              disabled: !enabled,
              checked: checked,
            ),
    TraySubmenu(
      label: final String label,
      entries: final List<TrayEntry> kids,
    ) =>
      MenuItem.submenu(
        label: label,
        submenu: Menu(items: kids.map(_toMenuItem).toList()),
      ),
  };

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final String? key = menuItem.key;
    if (key == null || key == _tooltipEntryId || _commands.isClosed) {
      return;
    }
    _commands.add(key);
  }

  @override
  void onTrayIconMouseDown() => _publish(TrayGesture.leftClick);

  @override
  void onTrayIconRightMouseDown() => _publish(TrayGesture.rightClick);

  void _publish(TrayGesture gesture) {
    if (!_gestures.isClosed) {
      _gestures.add(gesture);
    }
  }
}
