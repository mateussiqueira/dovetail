import 'dart:ffi';
import 'dart:io';

import 'package:dovetail_shortcut_channel/src/native/bindings.dart';
import 'package:dovetail_shortcut_channel/src/native/library_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

File _crateFile(String relative) =>
    File(p.join(Directory.current.path, 'rust', relative));

void main() {
  group('the press injector must not travel in a shipped build', () {
    test('the crate should not enable the probe by default', () {
      final String manifest = _crateFile('Cargo.toml').readAsStringSync();

      expect(manifest, contains('test-probe'));
      expect(
        RegExp(r'default\s*=\s*\[\s*\]').hasMatch(manifest),
        true,
        reason:
            'a feature listed in default is a feature every build gets, and '
            'this one lets any process holding the library synthesise a '
            'shortcut press',
      );
    });

    test('the export should be gated on that feature', () {
      // A superficie `extern "C"` mora em `presentation/`, desde as camadas.
      // O caminho e literal de proposito: se alguem mover o arquivo, este
      // teste tem de falhar em vez de procurar o simbolo em todo lugar e
      // aprovar por acaso.
      final String source = _crateFile(
        p.join('src', 'presentation', 'shortcut_ffi.rs'),
      ).readAsStringSync();
      final int gate = source.indexOf('#[cfg(feature = "test-probe")]');
      final int export = source.indexOf(ShortcutBindings.probeSymbol);

      expect(gate, isNot(-1));
      expect(
        gate,
        lessThan(export),
        reason: 'the attribute has to sit above the function it removes',
      );
    });

    test('the emitter itself should be gated too', () {
      expect(
        _crateFile(p.join('src', 'infra', 'event_pump.rs')).readAsStringSync(),
        contains('#[cfg(any(test, feature = "test-probe"))]'),
        reason:
            'an unexported function still compiles into the binary unless the '
            'attribute removes it',
      );
    });

    test('a library without the symbol should load, not refuse', () {
      final String? built = _builtLibrary();
      if (built == null) {
        markTestSkipped('the crate is not built for this run');
        return;
      }

      expect(
        () => ShortcutBindings(_open(built)),
        returnsNormally,
        reason:
            'the binding used to look the probe up eagerly, so removing it '
            'from the shipped build would have broken every construction',
      );
    });

    test('asking for a press without the symbol should say why', () {
      final String? built = _builtLibrary();
      if (built == null) {
        markTestSkipped('the crate is not built for this run');
        return;
      }

      final ShortcutBindings bindings = ShortcutBindings(_open(built));
      if (bindings.carriesProbe) {
        expect(
          bindings.carriesProbe,
          true,
          reason: 'this build was made with --features test-probe',
        );
        return;
      }

      expect(
        () => bindings.emitProbe(1, pressed: true),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('--features test-probe'),
          ),
        ),
      );
    });
  });
}

String? _builtLibrary() {
  final String name = Platform.isMacOS
      ? 'libdesktop_shortcut_channel.dylib'
      : Platform.isWindows
      ? 'dovetail_shortcut_channel.dll'
      : 'libdesktop_shortcut_channel.so';
  final File file = _crateFile(p.join('target', 'release', name));
  return file.existsSync() ? file.path : null;
}

DynamicLibrary _open(String path) => ShortcutLibrary.open(path: path);
