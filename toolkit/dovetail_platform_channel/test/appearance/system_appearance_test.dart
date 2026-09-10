import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tabela que o Dart e os três nativos têm de contar igual.
///
/// Os quatro arquivos escrevem os mesmos três números — `include/…
/// dovetail_system_appearance.h` define o enum em C, e cada plataforma o
/// devolve. Um deles trocar 1 por 2 é um app que abre claro quando o sistema
/// pediu escuro, na máquina de quem instalou e em lugar nenhum aqui.
///
/// O caso que mais convida ao erro está no Linux: o portal XDG usa `1` para
/// ESCURO e `2` para CLARO, invertido em relação a esta tabela. A tradução é
/// explícita lá, e este teste é o outro lado dela.
void main() {
  group('the native value', () {
    test('should map the three the header declares', () {
      expect(SystemAppearance.fromNative(0), SystemAppearance.unknown);
      expect(SystemAppearance.fromNative(1), SystemAppearance.light);
      expect(SystemAppearance.fromNative(2), SystemAppearance.dark);
    });

    test('should read anything else as unknown instead of throwing', () {
      for (final int stranger in <int>[-1, 3, 99, 1 << 30]) {
        expect(
          SystemAppearance.fromNative(stranger),
          SystemAppearance.unknown,
          reason:
              'a native newer than this Dart can answer a value it does not '
              'know yet. Bringing the app down over a colour is the wrong '
              'trade',
        );
      }
    });
  });

  group('the probe without a native', () {
    test('should report itself unavailable and answer unknown', () {
      const SystemAppearanceProbe probe = SystemAppearanceProbe.absent();

      expect(
        probe.isAvailable,
        false,
        reason:
            'this is a widget test: there is no plugin loaded, and the probe '
            'has to say so rather than pretend',
      );
      expect(probe.read(), SystemAppearance.unknown);
    });

    test('should never throw, however often it is asked', () {
      const SystemAppearanceProbe probe = SystemAppearanceProbe.absent();
      for (int i = 0; i < 3; i++) {
        expect(probe.read(), SystemAppearance.unknown);
      }
    });
  });

  group('the probe this host resolves', () {
    test('should be absent in a unit test, on every platform', () {
      final SystemAppearanceProbe probe = SystemAppearanceProbe();

      expect(
        probe.isAvailable,
        false,
        reason:
            'no plugin is loaded here, so there is no symbol to call. This is '
            'the assertion that catches the macOS trap: DynamicLibrary.'
            'process() ALWAYS opens there, because the pod links statically '
            'into the runner, so a probe that only asked "did the library '
            'open?" would report itself available in this very test and only '
            'find out otherwise when read',
      );
      expect(probe.read(), SystemAppearance.unknown);
    });
  });

  group('unknown', () {
    test('should be the first value, so the native zero lands on it', () {
      expect(
        SystemAppearance.values.first,
        SystemAppearance.unknown,
        reason:
            'the C header declares DovetailAppearanceUnknown = 0, and "could '
            'not tell" being the zero is what makes an uninitialised read, a '
            'missing registry key and an absent library all land in the same '
            'honest answer instead of on a colour',
      );
    });
  });
}
