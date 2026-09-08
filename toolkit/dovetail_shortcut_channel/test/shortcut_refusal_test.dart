import 'package:dovetail_shortcut_channel/dovetail_shortcut_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the refusals a caller can actually receive', () {
    test('every member should be produced by some path', () {
      expect(ShortcutRefusal.values, <ShortcutRefusal>[
        ShortcutRefusal.platformUnsupported,
        ShortcutRefusal.malformedChord,
        ShortcutRefusal.takenBySystem,
        ShortcutRefusal.alreadyBound,
        ShortcutRefusal.notBound,
        ShortcutRefusal.backendUnavailable,
        ShortcutRefusal.sessionUnsupported,
        ShortcutRefusal.refusedByPolicy,
      ]);
    });

    test('a code no member carries should throw, not fold into another', () {
      for (final int orphan in <int>[-3, -4, 9, 99]) {
        expect(
          () => ShortcutRefusal.fromStatus(orphan),
          throwsA(
            isA<ShortcutFailure>().having(
              (ShortcutFailure failure) => failure.detail,
              'detail',
              contains('does not know'),
            ),
          ),
          reason:
              '-3 and -4 were missingApplicationIdentity and refusedByUser, '
              'which only a portal backend can produce and no code here does; '
              'a future backend sending them should fail loudly rather than '
              'be read as some other cause',
        );
      }
    });

    test('the codes should match what the native side sends', () {
      expect(ShortcutRefusal.malformedChord.code, 1);
      expect(ShortcutRefusal.takenBySystem.code, 2);
      expect(ShortcutRefusal.alreadyBound.code, 3);
      expect(ShortcutRefusal.notBound.code, 4);
      expect(ShortcutRefusal.backendUnavailable.code, 5);
    });
  });
}
