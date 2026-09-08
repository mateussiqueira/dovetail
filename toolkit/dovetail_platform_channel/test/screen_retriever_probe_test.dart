import 'dart:ui';

import 'package:dovetail_platform_channel/src/display/screen_retriever_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:screen_retriever/screen_retriever.dart';

class ScreenRetrieverSpy extends Mock implements ScreenRetriever {}

Display _display({
  required String id,
  required Size size,
  Offset? visiblePosition,
  Size? visibleSize,
}) => Display(
  id: id,
  size: size,
  visiblePosition: visiblePosition,
  visibleSize: visibleSize,
);

void main() {
  late ScreenRetrieverSpy retriever;
  late ScreenRetrieverProbe probe;

  setUp(() {
    retriever = ScreenRetrieverSpy();
    probe = ScreenRetrieverProbe(retriever: retriever);
  });

  group('the work area it derives from a display', () {
    test('should use the visible rectangle when the platform gives one', () {
      expect(
        ScreenRetrieverProbe.workAreaOf(
          _display(
            id: 'a',
            size: const Size(1512, 982),
            visiblePosition: const Offset(0, 25),
            visibleSize: const Size(1512, 957),
          ),
        ),
        const Rect.fromLTWH(0, 25, 1512, 957),
        reason:
            'the menu bar and the dock are outside the visible area, and a '
            'panel placed over them is a panel the user cannot click',
      );
    });

    test('should fall back to the full size when there is no visible one', () {
      expect(
        ScreenRetrieverProbe.workAreaOf(
          _display(id: 'a', size: const Size(1920, 1080)),
        ),
        const Rect.fromLTWH(0, 0, 1920, 1080),
        reason:
            'a Linux compositor reports no visible area, and a null size read '
            'as zero would collapse the work area to a point',
      );
    });

    test('a visible position without a visible size should still work', () {
      expect(
        ScreenRetrieverProbe.workAreaOf(
          _display(
            id: 'a',
            size: const Size(1920, 1080),
            visiblePosition: const Offset(0, 32),
          ),
        ),
        const Rect.fromLTWH(0, 32, 1920, 1080),
      );
    });

    test('a monitor to the left of the primary should keep its origin', () {
      expect(
        ScreenRetrieverProbe.workAreaOf(
          _display(
            id: 'b',
            size: const Size(1920, 1080),
            visiblePosition: const Offset(-1920, 0),
            visibleSize: const Size(1920, 1050),
          ),
        ),
        const Rect.fromLTWH(-1920, 0, 1920, 1050),
        reason: 'a negative origin is an ordinary second monitor, not an error',
      );
    });
  });

  group('workAreaForPoint', () {
    setUp(() {
      when(() => retriever.getAllDisplays()).thenAnswer(
        (_) async => <Display>[
          _display(
            id: 'primary',
            size: const Size(1512, 982),
            visiblePosition: const Offset(0, 25),
            visibleSize: const Size(1512, 957),
          ),
          _display(
            id: 'left',
            size: const Size(1920, 1080),
            visiblePosition: const Offset(-1920, 0),
            visibleSize: const Size(1920, 1050),
          ),
        ],
      );
      when(() => retriever.getPrimaryDisplay()).thenAnswer(
        (_) async => _display(
          id: 'primary',
          size: const Size(1512, 982),
          visiblePosition: const Offset(0, 25),
          visibleSize: const Size(1512, 957),
        ),
      );
    });

    test('should find the monitor the point is on', () async {
      expect(
        await probe.workAreaForPoint(const Offset(-900, 400)),
        const Rect.fromLTWH(-1920, 0, 1920, 1050),
      );
      expect(
        await probe.workAreaForPoint(const Offset(700, 500)),
        const Rect.fromLTWH(0, 25, 1512, 957),
      );
    });

    test('a point on no monitor should fall back to the primary', () async {
      expect(
        await probe.workAreaForPoint(const Offset(9000, 9000)),
        const Rect.fromLTWH(0, 25, 1512, 957),
        reason:
            'a cursor read between two monitors, or on one unplugged between '
            'the read and the placement, must still put the panel somewhere',
      );
      verify(() => retriever.getPrimaryDisplay()).called(1);
    });

    test('a point in the menu bar belongs to no work area', () async {
      expect(
        await probe.workAreaForPoint(const Offset(700, 10)),
        const Rect.fromLTWH(0, 25, 1512, 957),
        reason:
            'the tray icon itself sits above the work area, so the point the '
            'panel is anchored to is outside every rectangle',
      );
    });
  });

  group('workAreas', () {
    test('should report one rectangle per monitor, in order', () async {
      when(() => retriever.getAllDisplays()).thenAnswer(
        (_) async => <Display>[
          _display(id: 'a', size: const Size(1512, 982)),
          _display(
            id: 'b',
            size: const Size(1920, 1080),
            visiblePosition: const Offset(1512, 0),
            visibleSize: const Size(1920, 1050),
          ),
        ],
      );

      expect(await probe.workAreas(), <Rect>[
        const Rect.fromLTWH(0, 0, 1512, 982),
        const Rect.fromLTWH(1512, 0, 1920, 1050),
      ]);
    });

    test('no monitors at all should be empty, not a throw', () async {
      when(
        () => retriever.getAllDisplays(),
      ).thenAnswer((_) async => <Display>[]);

      expect(await probe.workAreas(), isEmpty);
    });
  });

  group('cursorPoint', () {
    test('should report what the platform said', () async {
      when(
        () => retriever.getCursorScreenPoint(),
      ).thenAnswer((_) async => const Offset(1300, 25));

      expect(await probe.cursorPoint(), const Offset(1300, 25));
    });
  });
}
