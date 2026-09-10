import 'package:dovetail_privileged_helper/dovetail_privileged_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where a person is sent when the app cannot grant what it needs.
///
/// This is the half of the permission story that gets left out, and leaving it
/// out turns `requiresApproval` into a dead end: the app says "approve it" and
/// the person has nowhere to go.
void main() {
  group('the macOS pane', () {
    test('should be the Login Items pane, which is where macOS shows a daemon '
        'waiting for approval', () {
      final ApprovalPane pane = ApprovalPane.of(HelperHost.macos);

      expect(pane.exists, true);
      expect(
        pane.uri,
        'x-apple.systempreferences:com.apple.LoginItems-Settings.extension',
        reason:
            'System Settings pane identifiers are undocumented and have moved '
            'between releases. This is the assertion that fails loudly when '
            'somebody edits the string, and the Objective-C keeps a fallback '
            'to openSystemSettingsLoginItems for the day the string itself '
            'stops resolving',
      );
      expect(pane.absentBecause, isNull);
    });
  });

  group('the platforms with no pane', () {
    test('should say there is none, and say why, rather than guessing one', () {
      for (final HelperHost host in <HelperHost>[
        HelperHost.windows,
        HelperHost.linux,
        HelperHost.other,
      ]) {
        final ApprovalPane pane = ApprovalPane.of(host);

        expect(pane.exists, false, reason: host.name);
        expect(pane.uri, isNull, reason: host.name);
        expect(
          pane.absentBecause,
          isNotNull,
          reason:
              'without a sentence, a screen has nothing to put in place of '
              'the button it is not drawing: ${host.name}',
        );
      }
    });

    test('should explain Linux by the desktops not agreeing, not by an '
        'omission here', () {
      final ApprovalPane pane = ApprovalPane.of(HelperHost.linux);

      expect(pane.absentBecause, contains('desktop'));
    });
  });

  group('every host', () {
    test('should get a pane object, so no caller needs a null check', () {
      for (final HelperHost host in HelperHost.values) {
        expect(ApprovalPane.of(host), isNotNull, reason: host.name);
      }
    });
  });
}
