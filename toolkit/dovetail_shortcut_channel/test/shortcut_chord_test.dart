import 'package:dovetail_shortcut_channel/dovetail_shortcut_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShortcutChord', () {
    test('should render the accelerator the backend parses', () {
      expect(
        ShortcutChord(
          code: 'KeyV',
          modifiers: <ShortcutModifier>{
            ShortcutModifier.shift,
            ShortcutModifier.control,
          },
        ).accelerator,
        'Control+Shift+KeyV',
      );
    });

    test('the modifier order should not change the rendered accelerator', () {
      expect(
        ShortcutChord(
          code: 'KeyV',
          modifiers: <ShortcutModifier>{
            ShortcutModifier.shift,
            ShortcutModifier.control,
          },
        ).accelerator,
        ShortcutChord(
          code: 'KeyV',
          modifiers: <ShortcutModifier>{
            ShortcutModifier.control,
            ShortcutModifier.shift,
          },
        ).accelerator,
      );
    });

    test('should read back every accelerator it writes', () {
      for (final String accelerator in <String>[
        'Control+KeyV',
        'CommandOrControl+Shift+KeyK',
        'Meta+Alt+F4',
        'Control+Alt+Shift+Digit1',
      ]) {
        expect(ShortcutChord.parse(accelerator).accelerator, accelerator);
      }
    });

    test('should canonicalise the order the caller wrote', () {
      expect(
        ShortcutChord.parse('Shift+Alt+Control+KeyV').accelerator,
        'Control+Alt+Shift+KeyV',
      );
      expect(
        ShortcutChord.parse('Shift+CmdOrCtrl+KeyK').accelerator,
        'CommandOrControl+Shift+KeyK',
      );
    });

    test('should read the modifier spellings other tools print', () {
      expect(
        ShortcutChord.parse('Ctrl+KeyV'),
        ShortcutChord.parse('Control+KeyV'),
      );
      expect(
        ShortcutChord.parse('Cmd+KeyV'),
        ShortcutChord.parse('Super+KeyV'),
      );
      expect(
        ShortcutChord.parse('Option+Control+KeyV'),
        ShortcutChord.parse('Alt+Control+KeyV'),
      );
    });

    test('should refuse a chord with no key', () {
      expect(() => ShortcutChord(code: '  '), throwsA(isA<ShortcutFailure>()));
      expect(
        () => ShortcutChord.parse('  +  '),
        throwsA(isA<ShortcutFailure>()),
      );
    });

    test('should refuse modifiers smuggled inside the key name', () {
      expect(
        () => ShortcutChord(code: 'Control+KeyV'),
        throwsA(isA<ShortcutFailure>()),
      );
    });

    test('should refuse a modifier it does not know', () {
      expect(
        () => ShortcutChord.parse('Hyper+KeyV'),
        throwsA(isA<ShortcutFailure>()),
      );
    });

    test('two chords with the same meaning should be equal', () {
      expect(
        ShortcutChord.parse('Control+Shift+KeyV'),
        ShortcutChord.parse('Shift+Control+KeyV'),
      );
      expect(
        ShortcutChord.parse('Control+Shift+KeyV').hashCode,
        ShortcutChord.parse('Shift+Control+KeyV').hashCode,
      );
    });

    test('the modifier set should not be writable from outside', () {
      final ShortcutChord chord = ShortcutChord.parse('Control+KeyV');
      expect(
        () => chord.modifiers.add(ShortcutModifier.shift),
        throwsUnsupportedError,
      );
    });
  });

  group('ShortcutPolicy', () {
    const ShortcutPolicy policy = ShortcutPolicy();

    test('should accept a chord carrying a primary modifier', () {
      for (final ShortcutHost host in ShortcutHost.values) {
        expect(
          policy.refuse(ShortcutChord.parse('Control+Shift+KeyV'), host),
          isNull,
          reason: host.name,
        );
      }
    });

    test('should refuse a chord that is one keystroke from every app', () {
      expect(
        policy.refuse(ShortcutChord.parse('Shift+KeyV'), ShortcutHost.macos),
        isNotNull,
      );
      expect(
        policy.refuse(ShortcutChord.parse('KeyV'), ShortcutHost.windows),
        isNotNull,
      );
    });

    test('should refuse F12 on every host, not only on windows', () {
      for (final ShortcutHost host in ShortcutHost.values) {
        expect(
          policy.refuse(ShortcutChord.parse('Control+F12'), host),
          isNotNull,
          reason: host.name,
        );
      }
    });

    test('should refuse the windows key on windows and allow it elsewhere', () {
      final ShortcutChord chord = ShortcutChord.parse('Meta+Shift+KeyV');
      expect(policy.refuse(chord, ShortcutHost.windows), isNotNull);
      expect(policy.refuse(chord, ShortcutHost.linux), isNull);
      expect(policy.refuse(chord, ShortcutHost.macos), isNull);
    });

    test('should refuse an option-only chord on macos', () {
      expect(
        policy.refuse(
          ShortcutChord.parse('Alt+Shift+KeyV'),
          ShortcutHost.macos,
        ),
        isNotNull,
      );
      expect(
        policy.refuse(
          ShortcutChord.parse('Control+Alt+KeyV'),
          ShortcutHost.macos,
        ),
        isNull,
      );
    });

    test('enforce should throw the refusal reason, not a bare bool', () {
      expect(
        () => policy.enforce(
          ShortcutChord.parse('Shift+KeyV'),
          ShortcutHost.linux,
        ),
        throwsA(
          isA<ShortcutFailure>().having(
            (ShortcutFailure failure) => failure.reason,
            'reason',
            ShortcutRefusal.refusedByPolicy,
          ),
        ),
      );
    });
  });

  group('SessionProbe', () {
    ShortcutSupport linux(Map<String, String> environment) => SessionProbe(
      host: ShortcutHost.linux,
      environment: environment,
    ).probe();

    test('windows and macos should grant without asking anybody', () {
      for (final ShortcutHost host in <ShortcutHost>[
        ShortcutHost.windows,
        ShortcutHost.macos,
      ]) {
        final ShortcutSupport support = SessionProbe(
          host: host,
          environment: const <String, String>{},
        ).probe();
        expect(support.available, true);
        expect(support.applicationChoosesChord, true);
        expect(support.needsSystemPermission, false);
        expect(support.backend.grantsWithoutAsking, true);
      }
    });

    test('a declared x11 session should reach XGrabKey', () {
      expect(
        linux(const <String, String>{
          'XDG_SESSION_TYPE': 'x11',
          'DISPLAY': ':0',
        }).backend,
        ShortcutBackend.x11GrabKey,
      );
    });

    test('a compositor started from a tty should still be Wayland', () {
      final ShortcutSupport support = SessionProbe(
        host: ShortcutHost.linux,
        environment: const <String, String>{
          'XDG_SESSION_TYPE': 'tty',
          'WAYLAND_DISPLAY': 'wayland-1',
          'DISPLAY': ':0',
        },
      ).probe();

      expect(support.backend, ShortcutBackend.waylandPortal);
      expect(
        support.available,
        false,
        reason:
            'sway and hyprland launched from a console leave '
            'XDG_SESSION_TYPE at tty, and XWayland still sets DISPLAY; '
            'reading that as X11 grabs a key the compositor never delivers '
            'and reports success',
      );
    });

    test('a tty compositor with no XWayland should still be a session', () {
      final ShortcutSupport support = SessionProbe(
        host: ShortcutHost.linux,
        environment: const <String, String>{
          'XDG_SESSION_TYPE': 'tty',
          'WAYLAND_DISPLAY': 'wayland-1',
        },
      ).probe();

      expect(
        support.backend,
        ShortcutBackend.waylandPortal,
        reason:
            'answering none here tells the user there is no session to bind '
            'in, when there is one that needs the portal',
      );
    });

    test('a declared x11 session should win over a stale wayland socket', () {
      final ShortcutSupport support = SessionProbe(
        host: ShortcutHost.linux,
        environment: const <String, String>{
          'XDG_SESSION_TYPE': 'x11',
          'WAYLAND_DISPLAY': 'wayland-0',
          'DISPLAY': ':0',
        },
      ).probe();

      expect(support.backend, ShortcutBackend.x11GrabKey);
      expect(support.available, true);
    });

    test('a declared wayland session should not reach XGrabKey', () {
      final ShortcutSupport support = linux(const <String, String>{
        'XDG_SESSION_TYPE': 'wayland',
        'WAYLAND_DISPLAY': 'wayland-0',
        'DISPLAY': ':0',
        'XDG_CURRENT_DESKTOP': 'sway',
      });
      expect(support.backend, ShortcutBackend.waylandPortal);
      expect(support.available, false);
      expect(support.unavailableBecause, contains('sway'));
    });

    test('the declared session type should beat a stray DISPLAY', () {
      expect(
        linux(const <String, String>{
          'XDG_SESSION_TYPE': 'wayland',
          'DISPLAY': ':0',
        }).backend,
        ShortcutBackend.waylandPortal,
        reason:
            'under XWayland a DISPLAY exists but XGrabKey never sees the '
            'compositor keys, so it would report success and never fire',
      );
    });

    test('gnome over xorg should reach XGrabKey, not the portal', () {
      expect(
        linux(const <String, String>{
          'XDG_SESSION_TYPE': 'x11',
          'DISPLAY': ':0',
          'XDG_CURRENT_DESKTOP': 'GNOME',
        }).backend,
        ShortcutBackend.x11GrabKey,
      );
    });

    test('an undeclared session should be read from the sockets', () {
      expect(
        linux(const <String, String>{'WAYLAND_DISPLAY': 'wayland-0'}).backend,
        ShortcutBackend.waylandPortal,
      );
      expect(
        linux(const <String, String>{'DISPLAY': ':0'}).backend,
        ShortcutBackend.x11GrabKey,
      );
    });

    test('a session with neither should say there is nothing to bind in', () {
      final ShortcutSupport support = linux(const <String, String>{});
      expect(support.backend, ShortcutBackend.none);
      expect(support.available, false);
      expect(support.unavailableBecause, isNotNull);
    });

    test('an empty variable should count as unset', () {
      expect(
        linux(const <String, String>{
          'XDG_SESSION_TYPE': '',
          'DISPLAY': '',
          'WAYLAND_DISPLAY': '',
        }).backend,
        ShortcutBackend.none,
      );
    });

    test('a wayland session should say the user owns the chord', () {
      final ShortcutSupport support = linux(const <String, String>{
        'XDG_SESSION_TYPE': 'wayland',
      });
      expect(support.applicationChoosesChord, false);
      expect(support.userMayRebind, true);
      expect(support.needsSystemPermission, true);
    });
  });

  group('DisabledShortcutSurface', () {
    test('should refuse every request with the session reason', () async {
      final ShortcutSupport support = SessionProbe(
        host: ShortcutHost.linux,
        environment: const <String, String>{'XDG_SESSION_TYPE': 'wayland'},
      ).probe();

      final List<ShortcutOutcome> outcomes =
          await DisabledShortcutSurface(
            support,
            ShortcutRefusal.sessionUnsupported,
          ).bind(<ShortcutRequest>[
            ShortcutRequest(
              name: 'toggle',
              chord: ShortcutChord.parse('Control+Shift+KeyV'),
            ),
          ]);

      expect(outcomes.single, isA<ShortcutRefused>());
      expect(
        (outcomes.single as ShortcutRefused).reason,
        ShortcutRefusal.sessionUnsupported,
      );
      expect((outcomes.single as ShortcutRefused).detail, contains('portal'));
    });

    test('its press stream should be empty, not broken', () async {
      expect(
        await const DisabledShortcutSurface(
          ShortcutSupport(
            backend: ShortcutBackend.none,
            available: false,
            applicationChoosesChord: false,
            userMayRebind: false,
            needsSystemPermission: false,
            unavailableBecause: 'nothing here',
          ),
          ShortcutRefusal.platformUnsupported,
        ).presses().toList(),
        isEmpty,
      );
    });
  });
}
