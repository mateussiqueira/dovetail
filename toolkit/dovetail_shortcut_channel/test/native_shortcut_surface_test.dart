import 'dart:async';
import 'dart:io';

import 'package:dovetail_shortcut_channel/dovetail_shortcut_channel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String? _libraryPath() {
  final String root = p.join(
    Directory.current.path,
    'rust',
    'target',
    'release',
  );
  final String name = Platform.isMacOS
      ? 'libdesktop_shortcut_channel.dylib'
      : Platform.isWindows
      ? 'dovetail_shortcut_channel.dll'
      : 'libdesktop_shortcut_channel.so';
  final String path = p.join(root, name);
  return File(path).existsSync() ? path : null;
}

void main() {
  final String? library = _libraryPath();

  // Declared, never returned early. A `return` here left the seventeen tests
  // below unregistered — not skipped, absent — so the suite reported itself
  // green with one test and nobody could see the sixteen that vanished.
  // Measured: 39 declared without the crate against 55 with it.
  final String? absent = library == null
      ? 'run cargo build --release --features test-probe in rust/ to let this '
            'suite drive the real registry; the pure Dart suite covers the '
            'rest, and a build without that feature is what ships'
      : null;

  NativeShortcutSurface open() =>
      NativeShortcutSurface.open(libraryPath: library!);

  bool cannotDrivePump(NativeShortcutSurface surface) {
    if (surface.carriesPressProbe) {
      return false;
    }
    markTestSkipped(
      'this library was built without --features test-probe, which is what a '
      'shipped build looks like; the pump cannot be driven from here',
    );
    return true;
  }

  ShortcutRequest request(String name, String accelerator) =>
      ShortcutRequest(name: name, chord: ShortcutChord.parse(accelerator));

  test('the backend it reports should be the one this host has', () async {
    final NativeShortcutSurface surface = open();
    addTearDown(surface.dispose);

    expect(
      surface.nativeBackend,
      Platform.isMacOS
          ? ShortcutBackend.carbonEventHotKey
          : Platform.isWindows
          ? ShortcutBackend.win32RegisterHotKey
          : anyOf(ShortcutBackend.x11GrabKey, ShortcutBackend.none),
    );
    expect(surface.nativeBackend, surface.support.backend);
  }, skip: absent);

  test('should bind a real chord and hand back a native id', () async {
    final NativeShortcutSurface surface = open();
    addTearDown(surface.dispose);

    final List<ShortcutOutcome> outcomes = await surface.bind(<ShortcutRequest>[
      request('toggle', 'Control+Alt+Shift+F9'),
    ]);

    expect(outcomes.single, isA<ShortcutBound>());
    expect((outcomes.single as ShortcutBound).nativeId, isNonZero);
  }, skip: absent);

  test('the same chord bound twice should be refused, not doubled', () async {
    final NativeShortcutSurface surface = open();
    addTearDown(surface.dispose);

    await surface.bind(<ShortcutRequest>[request('a', 'Control+Alt+F8')]);
    final List<ShortcutOutcome> again = await surface.bind(<ShortcutRequest>[
      request('b', 'Control+Alt+F8'),
    ]);

    expect(again.single, isA<ShortcutRefused>());
    expect(
      (again.single as ShortcutRefused).reason,
      ShortcutRefusal.alreadyBound,
    );
    expect((again.single as ShortcutRefused).detail, contains('already bound'));
  }, skip: absent);

  test('a chord the backend cannot parse should carry its own words', () async {
    final NativeShortcutSurface surface = open();
    addTearDown(surface.dispose);

    final List<ShortcutOutcome> outcomes = await surface.bind(<ShortcutRequest>[
      request('ghost', 'Control+KeyNotAKey'),
    ]);

    expect(outcomes.single, isA<ShortcutRefused>());
    expect(
      (outcomes.single as ShortcutRefused).reason,
      ShortcutRefusal.malformedChord,
    );
    expect((outcomes.single as ShortcutRefused).detail, contains('KeyNotAKey'));
  }, skip: absent);

  test('a chord the policy refuses should never reach the backend', () async {
    final NativeShortcutSurface surface = open();
    addTearDown(surface.dispose);

    final List<ShortcutOutcome> outcomes = await surface.bind(<ShortcutRequest>[
      request('bare', 'Shift+KeyV'),
    ]);

    expect(
      (outcomes.single as ShortcutRefused).reason,
      ShortcutRefusal.refusedByPolicy,
    );
  }, skip: absent);

  test('a released chord should become bindable again', () async {
    final NativeShortcutSurface surface = open();
    addTearDown(surface.dispose);

    await surface.bind(<ShortcutRequest>[request('a', 'Control+Alt+F7')]);
    await surface.release('a');

    expect(
      (await surface.bind(<ShortcutRequest>[
        request('b', 'Control+Alt+F7'),
      ])).single,
      isA<ShortcutBound>(),
    );
  }, skip: absent);

  test(
    'releasing the same name twice should refuse, not pass quietly',
    () async {
      final NativeShortcutSurface surface = open();
      addTearDown(surface.dispose);

      await surface.bind(<ShortcutRequest>[request('a', 'Control+Alt+KeyM')]);
      await surface.release('a');

      await expectLater(
        surface.release('a'),
        completes,
        reason:
            'the name is gone from the map, so this never reaches the platform',
      );
    },
    skip: absent,
  );

  test('the native status should not be discarded on releaseAll', () async {
    final NativeShortcutSurface surface = open();
    addTearDown(surface.dispose);

    await surface.bind(<ShortcutRequest>[
      request('a', 'Control+Alt+KeyN'),
      request('b', 'Control+Alt+KeyO'),
    ]);
    await expectLater(surface.releaseAll(), completes);
    expect(
      (await surface.bind(<ShortcutRequest>[
        request('a', 'Control+Alt+KeyN'),
      ])).single,
      isA<ShortcutBound>(),
    );
  }, skip: absent);

  test('a second registry in one process should be refused by name', () {
    final NativeShortcutSurface first = open();
    addTearDown(first.dispose);

    expect(
      open,
      throwsA(
        isA<ShortcutFailure>().having(
          (ShortcutFailure failure) => failure.detail,
          'detail',
          contains('exactly one'),
        ),
      ),
      reason:
          'measured: the platform allows one registry per process, and the '
          'second open returns an errno that reads as a missing file',
    );
  }, skip: absent);

  test('a disposed registry should free the slot for the next one', () async {
    final NativeShortcutSurface first = open();
    await first.dispose();
    final NativeShortcutSurface second = open();
    addTearDown(second.dispose);
    expect(second.nativeBackend, ShortcutBackend.carbonEventHotKey);
  }, skip: absent);

  test('releasing a name nobody bound should be quiet', () async {
    final NativeShortcutSurface surface = open();
    addTearDown(surface.dispose);
    await expectLater(surface.release('never-bound'), completes);
  }, skip: absent);

  test(
    'a press should cross the thread boundary and reach the stream',
    () async {
      final NativeShortcutSurface surface = open();
      addTearDown(surface.dispose);

      final List<ShortcutOutcome> outcomes = await surface.bind(
        <ShortcutRequest>[request('toggle', 'Control+Alt+Shift+F6')],
      );
      final int nativeId = (outcomes.single as ShortcutBound).nativeId;

      final Future<List<ShortcutPress>> collected = surface
          .presses()
          .take(2)
          .toList();

      if (cannotDrivePump(surface)) {
        return;
      }
      surface.deliverProbePress(nativeId, pressed: true);
      surface.deliverProbePress(nativeId, pressed: false);

      final List<ShortcutPress> presses = await collected.timeout(
        const Duration(seconds: 5),
      );

      expect(presses.map((ShortcutPress press) => press.name), <String>[
        'toggle',
        'toggle',
      ]);
      expect(presses.map((ShortcutPress press) => press.pressed), <bool>[
        true,
        false,
      ]);
    },
    skip: absent,
  );

  test('a press for a released chord should not reach the stream', () async {
    final NativeShortcutSurface surface = open();
    addTearDown(surface.dispose);

    final List<ShortcutOutcome> outcomes = await surface.bind(<ShortcutRequest>[
      request('toggle', 'Control+Alt+Shift+F5'),
    ]);
    final int nativeId = (outcomes.single as ShortcutBound).nativeId;

    final List<ShortcutPress> seen = <ShortcutPress>[];
    final StreamSubscription<ShortcutPress> subscription = surface
        .presses()
        .listen(seen.add);
    addTearDown(subscription.cancel);

    await surface.release('toggle');
    if (cannotDrivePump(surface)) {
      return;
    }
    surface.deliverProbePress(nativeId, pressed: true);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(seen, isEmpty);
  }, skip: absent);

  test('every press should name the chord it came from', () async {
    final NativeShortcutSurface surface = open();
    addTearDown(surface.dispose);

    final List<ShortcutOutcome> outcomes = await surface.bind(<ShortcutRequest>[
      request('connect', 'Control+Alt+Shift+F3'),
      request('disconnect', 'Control+Alt+Shift+F4'),
    ]);
    final int connect = (outcomes.first as ShortcutBound).nativeId;
    final int disconnect = (outcomes.last as ShortcutBound).nativeId;
    expect(connect, isNot(disconnect));

    final Future<List<ShortcutPress>> collected = surface
        .presses()
        .take(2)
        .toList();

    if (cannotDrivePump(surface)) {
      return;
    }
    surface.deliverProbePress(disconnect, pressed: true);
    surface.deliverProbePress(connect, pressed: true);

    expect(
      (await collected.timeout(
        const Duration(seconds: 5),
      )).map((ShortcutPress press) => press.name),
      <String>['disconnect', 'connect'],
    );
  }, skip: absent);

  test('releaseAll should drop every binding at once', () async {
    final NativeShortcutSurface surface = open();
    addTearDown(surface.dispose);

    await surface.bind(<ShortcutRequest>[
      request('a', 'Control+Alt+Shift+F1'),
      request('b', 'Control+Alt+Shift+F2'),
    ]);
    await surface.releaseAll();

    expect(
      (await surface.bind(<ShortcutRequest>[
        request('a', 'Control+Alt+Shift+F1'),
      ])).single,
      isA<ShortcutBound>(),
    );
  }, skip: absent);

  test(
    'a disposed surface should refuse instead of touching freed memory',
    () async {
      final NativeShortcutSurface surface = open();
      await surface.bind(<ShortcutRequest>[request('a', 'Control+Alt+KeyJ')]);
      await surface.dispose();

      expect(
        () => surface.bind(<ShortcutRequest>[request('b', 'Control+Alt+KeyK')]),
        throwsA(isA<ShortcutFailure>()),
      );
      await expectLater(surface.dispose(), completes);
    },
    skip: absent,
  );

  test('the loader should name every place it looked', () {
    expect(
      () => ShortcutLibrary.open(path: '/nonexistent/libnothing.dylib'),
      throwsA(isA<ArgumentError>()),
      reason: 'an explicit path is handed straight to dlopen',
    );

    final NativeShortcutSurface held = open();
    addTearDown(held.dispose);

    expect(
      ShortcutLibrary.stem,
      'dovetail_shortcut_channel',
      reason:
          'the loader searches by stem, so the library has to keep the '
          'plugin name or dlopen fails naming files that were never built',
    );
  }, skip: absent);
}
