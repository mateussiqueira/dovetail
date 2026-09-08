import 'dart:io';
import 'dart:ui';

import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter_test/flutter_test.dart';

const Rect _laptop = Rect.fromLTWH(0, 0, 1512, 982);
const Rect _external = Rect.fromLTWH(1512, -200, 2560, 1440);

void main() {
  group('the placement round trip', () {
    test('should survive encode and decode', () {
      const WindowPlacement sut = WindowPlacement(
        size: Size(1200, 720),
        position: Offset(64, 32),
        maximized: true,
        restoredSize: Size(1024, 640),
        restoredPosition: Offset(10, 20),
      );

      expect(WindowPlacement.decode(sut.encode()), sut);
    });

    test('should treat a payload that is not an object as unknown', () {
      expect(WindowPlacement.decode('[]'), const WindowPlacement.unknown());
    });

    test('should drop a size that is zero or negative', () {
      expect(WindowPlacement.decode('{"width":0,"height":720}').size, null);
      expect(WindowPlacement.decode('{"width":-5,"height":720}').size, null);
    });

    test(
      'should accept a negative position, which a left monitor produces',
      () {
        expect(
          WindowPlacement.decode('{"x":-1400,"y":-200}').position,
          const Offset(-1400, -200),
        );
      },
    );

    test('should ignore a half written pair instead of guessing', () {
      expect(WindowPlacement.decode('{"width":1200}').size, null);
      expect(WindowPlacement.decode('{"x":10}').position, null);
    });

    test('unknown should be empty and empty should not be persisted', () {
      expect(const WindowPlacement.unknown().isEmpty, true);
    });
  });

  group('the guard against a monitor that went away', () {
    test('should keep a placement fully inside a screen', () {
      const WindowPlacement sut = WindowPlacement(
        size: Size(1200, 720),
        position: Offset(100, 100),
        maximized: false,
      );

      expect(PlacementGuard.clampToScreens(sut, <Rect>[_laptop]), sut);
    });

    test(
      'should keep a placement on a second monitor while it is connected',
      () {
        const WindowPlacement sut = WindowPlacement(
          size: Size(1200, 720),
          position: Offset(1800, 0),
          maximized: false,
        );

        expect(
          PlacementGuard.clampToScreens(sut, <Rect>[_laptop, _external]),
          sut,
        );
      },
    );

    test('should drop the position when that monitor is gone', () {
      const WindowPlacement sut = WindowPlacement(
        size: Size(1200, 720),
        position: Offset(1800, 0),
        maximized: false,
      );

      final WindowPlacement guarded = PlacementGuard.clampToScreens(sut, <Rect>[
        _laptop,
      ]);

      expect(guarded.position, null);
      expect(guarded.size, const Size(1200, 720));
    });

    test('should keep the maximized flag when it drops the position', () {
      const WindowPlacement sut = WindowPlacement(
        size: Size(1200, 720),
        position: Offset(9000, 9000),
        maximized: true,
      );

      expect(
        PlacementGuard.clampToScreens(sut, <Rect>[_laptop]).maximized,
        true,
      );
    });

    test('should reject a window hanging off the edge by a sliver', () {
      const WindowPlacement sut = WindowPlacement(
        size: Size(1200, 720),
        position: Offset(1502, 500),
        maximized: false,
      );

      expect(
        PlacementGuard.clampToScreens(sut, <Rect>[_laptop]).position,
        null,
        reason:
            'ten visible pixels is not a reachable window; Tauri accepts any '
            'intersection and leaves the user with a title bar they cannot grab',
      );
    });

    test('should accept a window overlapping the edge by enough to grab', () {
      const WindowPlacement sut = WindowPlacement(
        size: Size(1200, 720),
        position: Offset(1300, 500),
        maximized: false,
      );

      expect(
        PlacementGuard.clampToScreens(sut, <Rect>[_laptop]).position,
        const Offset(1300, 500),
      );
    });

    test('should drop the position when no screen is reported at all', () {
      const WindowPlacement sut = WindowPlacement(
        size: Size(1200, 720),
        position: Offset(100, 100),
        maximized: false,
      );

      expect(PlacementGuard.clampToScreens(sut, const <Rect>[]).position, null);
    });

    test('should leave a placement with no position alone', () {
      const WindowPlacement sut = WindowPlacement(
        size: Size(1200, 720),
        position: null,
        maximized: false,
      );

      expect(PlacementGuard.clampToScreens(sut, <Rect>[_laptop]), sut);
    });
  });

  group('the file backed store', () {
    late Directory root;
    late FileWindowStateStore sut;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dovetail_window');
      sut = FileWindowStateStore(directory: root.path);
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('load should answer unknown before anything was saved', () {
      expect(sut.load(), const WindowPlacement.unknown());
    });

    test('save then load should return what was saved', () {
      const WindowPlacement placement = WindowPlacement(
        size: Size(1200, 720),
        position: Offset(64, 32),
        maximized: false,
      );

      sut.save(placement);

      expect(sut.load(), placement);
    });

    test('save should create the directory it was pointed at', () {
      final FileWindowStateStore nested = FileWindowStateStore(
        directory: '${root.path}/a/b/c',
      );

      nested.save(
        const WindowPlacement(
          size: Size(800, 600),
          position: Offset.zero,
          maximized: false,
        ),
      );

      expect(File(nested.path).existsSync(), true);
    });

    test('save should skip an empty placement rather than write noise', () {
      sut.save(const WindowPlacement.unknown());

      expect(File(sut.path).existsSync(), false);
    });

    test('load should answer unknown for a corrupt file, not throw', () {
      File(sut.path).writeAsStringSync('{ this is not json');

      expect(sut.load(), const WindowPlacement.unknown());
    });

    test('clear should remove the file and be safe to repeat', () {
      sut.save(
        const WindowPlacement(
          size: Size(800, 600),
          position: Offset.zero,
          maximized: false,
        ),
      );

      sut.clear();
      sut.clear();

      expect(File(sut.path).existsSync(), false);
    });
  });
}
