import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:dovetail_platform_channel/src/tray/tray_manager_surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tray_manager/tray_manager.dart';

class TrayManagerSpy extends Mock implements TrayManager {}

void main() {
  late TrayManagerSpy manager;

  setUpAll(() {
    registerFallbackValue(Menu());
  });

  setUp(() {
    manager = TrayManagerSpy();
    when(() => manager.setIcon(any())).thenAnswer((_) async {});
    when(() => manager.setToolTip(any())).thenAnswer((_) async {});
    when(() => manager.setContextMenu(any())).thenAnswer((_) async {});
    when(() => manager.destroy()).thenAnswer((_) async {});
  });

  TrayManagerSurface sutFor(TargetPlatform platform) => TrayManagerSurface(
    manager: manager,
    capabilities: PlatformCapabilities(platform),
  );

  List<MenuItem> lastMenu() {
    final Menu menu =
        verify(() => manager.setContextMenu(captureAny())).captured.last
            as Menu;
    return menu.items ?? const <MenuItem>[];
  }

  test('attach should set the icon and the menu once', () async {
    final TrayManagerSurface sut = sutFor(TargetPlatform.macOS);

    await sut.attach(
      icon: const TrayIconAsset('assets/tray.png'),
      menu: const <TrayEntry>[TrayCommand(id: 'quit', label: 'Quit')],
    );

    verify(() => manager.setIcon('assets/tray.png')).called(1);
    expect(lastMenu().single.key, 'quit');
  });

  test('setTooltip should reach the system tray on macOS', () async {
    final TrayManagerSurface sut = sutFor(TargetPlatform.macOS);

    await sut.setTooltip('no internet');

    expect(sut.supportsTooltip, true);
    verify(() => manager.setToolTip('no internet')).called(1);
    verifyNever(() => manager.setContextMenu(any()));
  });

  test(
    'setTooltip should fall back to a disabled menu entry on linux',
    () async {
      final TrayManagerSurface sut = sutFor(TargetPlatform.linux);

      await sut.setTooltip('no internet');

      expect(sut.supportsTooltip, false);
      verifyNever(() => manager.setToolTip(any()));

      final List<MenuItem> items = lastMenu();
      expect(items.first.label, 'no internet');
      expect(items.first.disabled, true);
    },
  );

  test(
    'the linux fallback should keep the app menu below the tooltip',
    () async {
      final TrayManagerSurface sut = sutFor(TargetPlatform.linux);

      await sut.setMenu(const <TrayEntry>[
        TrayCommand(id: 'connect', label: 'Connect'),
        TraySeparator(),
        TrayCommand(id: 'quit', label: 'Quit'),
      ]);
      await sut.setTooltip('no internet');

      final List<MenuItem> items = lastMenu();
      expect(items.length, 5);
      expect(items[0].label, 'no internet');
      expect(items[2].key, 'connect');
      expect(items[4].key, 'quit');
    },
  );

  test(
    'a command without a checked value should not become a checkbox',
    () async {
      final TrayManagerSurface sut = sutFor(TargetPlatform.windows);

      await sut.setMenu(const <TrayEntry>[
        TrayCommand(id: 'open', label: 'Open'),
      ]);

      expect(lastMenu().single.type, 'normal');
    },
  );

  test('a command with a checked value should become a checkbox', () async {
    final TrayManagerSurface sut = sutFor(TargetPlatform.windows);

    await sut.setMenu(const <TrayEntry>[
      TrayCommand(id: 'autostart', label: 'Start with system', checked: true),
    ]);

    final MenuItem item = lastMenu().single;
    expect(item.type, 'checkbox');
    expect(item.checked, true);
  });

  test('commands should publish the clicked entry id', () async {
    final TrayManagerSurface sut = sutFor(TargetPlatform.macOS);
    final Future<String> next = sut.commands().first;

    sut.onTrayMenuItemClick(MenuItem(key: 'connect', label: 'Connect'));

    expect(await next, 'connect');
  });

  test('commands should stay silent for the linux tooltip entry', () async {
    final TrayManagerSurface sut = sutFor(TargetPlatform.linux);
    final List<String> seen = <String>[];
    sut.commands().listen(seen.add);

    await sut.setTooltip('no internet');
    final MenuItem tooltipEntry = lastMenu().first;
    sut.onTrayMenuItemClick(tooltipEntry);
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty);
  });

  test('gestures should publish left and right clicks', () async {
    final TrayManagerSurface sut = sutFor(TargetPlatform.windows);
    final Future<List<TrayGesture>> collected = sut.gestures().take(2).toList();

    sut.onTrayIconMouseDown();
    sut.onTrayIconRightMouseDown();

    expect(await collected, <TrayGesture>[
      TrayGesture.leftClick,
      TrayGesture.rightClick,
    ]);
  });

  _gestureGroup();
}

void _gestureGroup() {
  group('the gestures the tray can actually report', () {
    test('should be only what the plugin publishes', () {
      expect(
        TrayGesture.values,
        <TrayGesture>[TrayGesture.leftClick, TrayGesture.rightClick],
        reason:
            'tray_manager offers mouse down and up for each button and no '
            'double-click callback at all, so a doubleClick member named a '
            'gesture nothing beneath this layer can see',
      );
    });
  });
}
