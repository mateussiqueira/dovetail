import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tabela que o Dart, o Objective-C e o C++ têm de contar igual.
///
/// `include/dovetail_platform_channel/dovetail_notification_permission.h`
/// declara os cinco números; o macOS os devolve por canal de método e o
/// Windows por FFI. Um dos três trocar `denied` por `granted` é uma tela que
/// manda a pessoa aos Ajustes liberar o que já está liberado — e isso só
/// aparece na máquina de quem instalou.
void main() {
  group('the native value', () {
    test('should map the five the header declares', () {
      expect(PermissionState.fromNative(0), PermissionState.unsupported);
      expect(PermissionState.fromNative(1), PermissionState.notDetermined);
      expect(PermissionState.fromNative(2), PermissionState.granted);
      expect(PermissionState.fromNative(3), PermissionState.denied);
      expect(PermissionState.fromNative(4), PermissionState.restricted);
    });

    test('should read anything else as unsupported instead of throwing', () {
      for (final int stranger in <int>[-1, 5, 99, 1 << 30]) {
        expect(
          PermissionState.fromNative(stranger),
          PermissionState.unsupported,
          reason:
              'a native newer than this Dart can answer a state it does not '
              'know yet. Reading it as a refusal would hide notifications '
              'that are being delivered',
        );
      }
    });

    test('unsupported should be the first value, so the zero lands on it', () {
      expect(
        PermissionState.values.first,
        PermissionState.unsupported,
        reason:
            'the C header declares Unsupported = 0, and an uninitialised read, '
            'a library that did not load and a platform with no permission '
            'model all land on the one answer that invents neither a grant '
            'nor a refusal',
      );
    });
  });

  group('mayAsk', () {
    test('should be true only where the system still shows the dialog', () {
      expect(PermissionState.notDetermined.mayAsk, true);
      for (final PermissionState settled in <PermissionState>[
        PermissionState.granted,
        PermissionState.denied,
        PermissionState.restricted,
        PermissionState.unsupported,
      ]) {
        expect(
          settled.mayAsk,
          false,
          reason:
              'macOS does not show the dialog twice. A UI that offered "ask" '
              'on $settled would be a button that does nothing, and nobody '
              'would learn why',
        );
      }
    });
  });

  group('mayDeliver', () {
    test('should let granted and unsupported through', () {
      expect(PermissionState.granted.mayDeliver, true);
      expect(
        PermissionState.unsupported.mayDeliver,
        true,
        reason:
            'unsupported is Linux, which notifies without asking anyone, and '
            'it is an app whose native is not loaded. Refusing to deliver in '
            'either case would delete notifications that work',
      );
    });

    test('should stop the three that will not arrive', () {
      expect(PermissionState.notDetermined.mayDeliver, false);
      expect(PermissionState.denied.mayDeliver, false);
      expect(PermissionState.restricted.mayDeliver, false);
    });
  });

  group('settingsCanRecoverIt', () {
    test('should be denied and nothing else', () {
      expect(PermissionState.denied.settingsCanRecoverIt, true);
      expect(
        PermissionState.restricted.settingsCanRecoverIt,
        false,
        reason:
            'restricted is a policy, not a choice. Sending someone to a '
            'settings pane where the control is greyed out is worse than '
            'saying nothing',
      );
      expect(PermissionState.notDetermined.settingsCanRecoverIt, false);
      expect(PermissionState.granted.settingsCanRecoverIt, false);
      expect(PermissionState.unsupported.settingsCanRecoverIt, false);
    });
  });
}
