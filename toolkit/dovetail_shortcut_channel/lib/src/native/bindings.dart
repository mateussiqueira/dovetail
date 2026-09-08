import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef ShortcutListener = void Function(int id, int pressed);
typedef NativeShortcutListener = Void Function(Uint32, Uint8);

final class ShortcutBindings {
  ShortcutBindings(DynamicLibrary library)
    : _backend = library.lookupFunction<Int32 Function(), int Function()>(
        'dovetail_shortcut_backend',
      ),
      _open = library
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'dovetail_shortcut_open',
          ),
      _close = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('dovetail_shortcut_close'),
      _bind = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint32>),
            int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint32>)
          >('dovetail_shortcut_bind'),
      _release = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Uint32),
            int Function(Pointer<Void>, int)
          >('dovetail_shortcut_release'),
      _releaseAll = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('dovetail_shortcut_release_all'),
      _lastFailure = library
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>),
            Pointer<Utf8> Function(Pointer<Void>)
          >('dovetail_shortcut_last_failure'),
      _listen = library
          .lookupFunction<
            Int32 Function(Pointer<NativeFunction<NativeShortcutListener>>),
            int Function(Pointer<NativeFunction<NativeShortcutListener>>)
          >('dovetail_shortcut_listen'),
      _lastOpenFailure = library
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'dovetail_shortcut_last_open_failure',
          ),
      _emitProbe = _optionalProbe(library);

  final int Function() _backend;
  final Pointer<Void> Function() _open;
  final void Function(Pointer<Void>) _close;
  final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint32>) _bind;
  final int Function(Pointer<Void>, int) _release;
  final int Function(Pointer<Void>) _releaseAll;
  final Pointer<Utf8> Function(Pointer<Void>) _lastFailure;
  final int Function(Pointer<NativeFunction<NativeShortcutListener>>) _listen;
  final Pointer<Utf8> Function() _lastOpenFailure;
  final void Function(int, int)? _emitProbe;

  static const String probeSymbol = 'dovetail_shortcut_emit_probe';

  static void Function(int, int)? _optionalProbe(DynamicLibrary library) {
    try {
      return library.lookupFunction<
        Void Function(Uint32, Uint8),
        void Function(int, int)
      >(probeSymbol);
    } on ArgumentError {
      return null;
    }
  }

  bool get carriesProbe => _emitProbe != null;

  String? lastOpenFailure() {
    final Pointer<Utf8> reason = _lastOpenFailure();
    return reason == nullptr ? null : reason.toDartString();
  }

  int backend() => _backend();

  Pointer<Void> open() => _open();

  void close(Pointer<Void> registry) => _close(registry);

  int bind(Pointer<Void> registry, String accelerator, Pointer<Uint32> outId) {
    final Pointer<Utf8> encoded = accelerator.toNativeUtf8();
    try {
      return _bind(registry, encoded, outId);
    } finally {
      calloc.free(encoded);
    }
  }

  int release(Pointer<Void> registry, int id) => _release(registry, id);

  int releaseAll(Pointer<Void> registry) => _releaseAll(registry);

  String? lastFailure(Pointer<Void> registry) {
    final Pointer<Utf8> reason = _lastFailure(registry);
    return reason == nullptr ? null : reason.toDartString();
  }

  int listen(NativeCallable<NativeShortcutListener> callable) =>
      _listen(callable.nativeFunction);

  int stopListening() => _listen(nullptr);

  void emitProbe(int id, {required bool pressed}) {
    final void Function(int, int)? emit = _emitProbe;
    if (emit == null) {
      throw StateError(
        'this library carries no $probeSymbol, which is how a shipped build '
        'should look. Rebuild the crate with --features test-probe to drive '
        'the pump from a test.',
      );
    }
    emit(id, pressed ? 1 : 0);
  }
}
