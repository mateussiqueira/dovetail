import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:dovetail_shortcut_channel/src/global_shortcut_surface.dart';
import 'package:dovetail_shortcut_channel/src/native/bindings.dart';
import 'package:dovetail_shortcut_channel/src/native/library_loader.dart';
import 'package:dovetail_shortcut_channel/src/session_probe.dart';
import 'package:dovetail_shortcut_channel/src/shortcut_backend.dart';
import 'package:dovetail_shortcut_channel/src/shortcut_policy.dart';
import 'package:dovetail_shortcut_channel/src/shortcut_refusal.dart';
import 'package:ffi/ffi.dart';

final class NativeShortcutSurface implements GlobalShortcutSurface {
  NativeShortcutSurface._(
    this._bindings,
    this._registry,
    this.support,
    this._host,
    this._policy,
  );

  factory NativeShortcutSurface.open({
    String? libraryPath,
    ShortcutHost? host,
    Map<String, String>? environment,
    ShortcutPolicy policy = const ShortcutPolicy(),
  }) {
    final ShortcutHost resolvedHost = host ?? currentShortcutHost();
    final ShortcutSupport support = SessionProbe(
      host: resolvedHost,
      environment: environment ?? Platform.environment,
    ).probe();

    if (_live != null) {
      throw const ShortcutFailure(
        ShortcutRefusal.backendUnavailable,
        'a shortcut registry is already open in this process, and the platform '
        'allows exactly one. Measured: a second open fails with an errno that '
        'reads as a missing file, which sends the reader hunting the wrong '
        'bug. Dispose the first surface before opening another.',
      );
    }

    final ShortcutBindings bindings = ShortcutBindings(
      ShortcutLibrary.open(path: libraryPath),
    );
    final Pointer<Void> registry = bindings.open();
    if (registry == nullptr) {
      throw ShortcutFailure(
        ShortcutRefusal.backendUnavailable,
        bindings.lastOpenFailure() ??
            'the platform refused to open a shortcut registry and gave no '
                'reason. On macOS the usual cause is a call that did not come '
                'from the main thread, where registration reports success and '
                'never fires.',
      );
    }

    final NativeShortcutSurface surface = NativeShortcutSurface._(
      bindings,
      registry,
      support,
      resolvedHost,
      policy,
    );
    _live = surface;
    return surface;
  }

  static NativeShortcutSurface? _live;

  final ShortcutBindings _bindings;
  final ShortcutHost _host;
  final ShortcutPolicy _policy;
  final Map<int, String> _namesByNativeId = <int, String>{};
  final Map<String, int> _nativeIdsByName = <String, int>{};
  final StreamController<ShortcutPress> _presses =
      StreamController<ShortcutPress>.broadcast();

  Pointer<Void> _registry;
  NativeCallable<NativeShortcutListener>? _callable;
  bool _disposed = false;

  @override
  final ShortcutSupport support;

  ShortcutBackend get nativeBackend =>
      ShortcutBackend.fromCode(_bindings.backend());

  @override
  Stream<ShortcutPress> presses() {
    _installListener();
    return _presses.stream;
  }

  @override
  Future<List<ShortcutOutcome>> bind(List<ShortcutRequest> requests) async {
    _refuseAfterDispose();
    final List<ShortcutOutcome> outcomes = <ShortcutOutcome>[];
    for (final ShortcutRequest request in requests) {
      outcomes.add(_bindOne(request));
    }
    return List<ShortcutOutcome>.unmodifiable(outcomes);
  }

  @override
  Future<void> release(String name) async {
    _refuseAfterDispose();
    final int? nativeId = _nativeIdsByName.remove(name);
    if (nativeId == null) {
      return;
    }
    final int status = _bindings.release(_registry, nativeId);
    if (status != 0) {
      _nativeIdsByName[name] = nativeId;
      throw ShortcutFailure(
        ShortcutRefusal.fromStatus(status),
        _bindings.lastFailure(_registry) ??
            'the platform refused to release "$name" and gave no reason',
      );
    }
    _namesByNativeId.remove(nativeId);
  }

  @override
  Future<void> releaseAll() async {
    _refuseAfterDispose();
    final int status = _bindings.releaseAll(_registry);
    if (status != 0) {
      throw ShortcutFailure(
        ShortcutRefusal.fromStatus(status),
        _bindings.lastFailure(_registry) ??
            'the platform refused to release every shortcut and gave no reason',
      );
    }
    _nativeIdsByName.clear();
    _namesByNativeId.clear();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_live == this) {
      _live = null;
    }
    _bindings.stopListening();
    _callable?.close();
    _callable = null;
    _bindings.close(_registry);
    _registry = nullptr;
    _nativeIdsByName.clear();
    _namesByNativeId.clear();
    await _presses.close();
  }

  bool get carriesPressProbe => _bindings.carriesProbe;

  void deliverProbePress(int nativeId, {required bool pressed}) =>
      _bindings.emitProbe(nativeId, pressed: pressed);

  ShortcutOutcome _bindOne(ShortcutRequest request) {
    if (!support.available) {
      return ShortcutRefused(
        request.name,
        support.backend == ShortcutBackend.waylandPortal
            ? ShortcutRefusal.sessionUnsupported
            : ShortcutRefusal.platformUnsupported,
        support.unavailableBecause ?? 'this session grants no shortcut',
      );
    }

    final String? refusal = _policy.refuse(request.chord, _host);
    if (refusal != null) {
      return ShortcutRefused(
        request.name,
        ShortcutRefusal.refusedByPolicy,
        refusal,
      );
    }

    final Pointer<Uint32> outId = calloc<Uint32>();
    try {
      final int status = _bindings.bind(
        _registry,
        request.chord.accelerator,
        outId,
      );
      if (status != 0) {
        return ShortcutRefused(
          request.name,
          ShortcutRefusal.fromStatus(status),
          _bindings.lastFailure(_registry) ?? 'the platform gave no reason',
        );
      }

      final int nativeId = outId.value;
      _namesByNativeId[nativeId] = request.name;
      _nativeIdsByName[request.name] = nativeId;
      _installListener();
      return ShortcutBound(request.name, request.chord, nativeId);
    } finally {
      calloc.free(outId);
    }
  }

  void _installListener() {
    if (_callable != null || _disposed) {
      return;
    }
    final NativeCallable<NativeShortcutListener> callable =
        NativeCallable<NativeShortcutListener>.listener(_onNativePress);
    final int status = _bindings.listen(callable);
    if (status != 0) {
      callable.close();
      throw ShortcutFailure(
        ShortcutRefusal.fromStatus(status),
        'the platform could not start delivering key presses, so a bound '
        'shortcut would never reach the application',
      );
    }
    _callable = callable;
  }

  void _onNativePress(int nativeId, int pressed) {
    final String? name = _namesByNativeId[nativeId];
    if (name == null || _presses.isClosed) {
      return;
    }
    _presses.add(ShortcutPress(name: name, pressed: pressed != 0));
  }

  void _refuseAfterDispose() {
    if (_disposed) {
      throw const ShortcutFailure(
        ShortcutRefusal.backendUnavailable,
        'this surface was disposed; its registry is closed',
      );
    }
  }
}

ShortcutHost currentShortcutHost() {
  if (Platform.isWindows) {
    return ShortcutHost.windows;
  }
  if (Platform.isMacOS) {
    return ShortcutHost.macos;
  }
  if (Platform.isLinux) {
    return ShortcutHost.linux;
  }
  return ShortcutHost.other;
}
