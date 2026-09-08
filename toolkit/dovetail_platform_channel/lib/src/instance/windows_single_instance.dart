import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:dovetail_platform_channel/src/instance/forwarded_launch.dart';
import 'package:dovetail_platform_channel/src/instance/single_instance.dart';
import 'package:dovetail_platform_channel/src/instance/single_instance_verdict.dart';
import 'package:ffi/ffi.dart';

typedef _ClaimNative =
    int Function(Pointer<Utf16>, Pointer<Pointer<Utf16>>, int);
typedef _TakeNative = Pointer<Utf16> Function(Pointer<Int32>);
typedef _FreeNative = void Function(Pointer<Utf16>);
typedef _ReleaseNative = void Function();

const String _libraryName = 'dovetail_platform_channel.dll';
const String _fieldSeparator = '\u0000\u0000';
const String _argumentSeparator = '\u0000';

final class WindowsSingleInstance implements SingleInstance {
  WindowsSingleInstance({
    required this.instanceKey,
    DynamicLibrary? library,
    this.pollInterval = const Duration(milliseconds: 400),
  }) : _library = library ?? _open();

  final String instanceKey;
  final Duration pollInterval;
  final DynamicLibrary? _library;

  final StreamController<ForwardedLaunch> _forwarded =
      StreamController<ForwardedLaunch>.broadcast();

  Timer? _poll;

  bool get isAvailable => _library != null;

  @override
  Stream<ForwardedLaunch> launches() => _forwarded.stream;

  @override
  Future<SingleInstanceVerdict> claim({
    List<String> arguments = const <String>[],
    String? workingDirectory,
  }) async {
    final DynamicLibrary? library = _library;
    if (library == null) {
      return SingleInstanceVerdict.unavailable;
    }

    final SingleInstanceVerdict verdict = readVerdict(
      _claimThrough(library, arguments),
    );
    if (verdict == SingleInstanceVerdict.primary) {
      _poll = Timer.periodic(pollInterval, (Timer _) => drain());
    }
    return verdict;
  }

  @override
  Future<void> release() async {
    _poll?.cancel();
    _poll = null;

    final DynamicLibrary? library = _library;
    if (library == null) {
      return;
    }
    library.lookupFunction<Void Function(), _ReleaseNative>(
      'DovetailReleasePrimaryInstance',
    )();
  }

  @override
  Future<void> dispose() async {
    await release();
    await _forwarded.close();
  }

  void drain() {
    if (_forwarded.isClosed || !_forwarded.hasListener) {
      return;
    }
    for (
      ForwardedLaunch? launch = takeForwardedLaunch();
      launch != null;
      launch = takeForwardedLaunch()
    ) {
      _forwarded.add(launch);
    }
  }

  SingleInstanceVerdict readVerdict(int nativeVerdict) =>
      switch (nativeVerdict) {
        0 => SingleInstanceVerdict.primary,
        1 => SingleInstanceVerdict.secondary,
        _ => SingleInstanceVerdict.unavailable,
      };

  ForwardedLaunch? takeForwardedLaunch() {
    final DynamicLibrary? library = _library;
    if (library == null) {
      return null;
    }

    final _TakeNative take = library
        .lookupFunction<Pointer<Utf16> Function(Pointer<Int32>), _TakeNative>(
          'DovetailTakeForwardedLaunch',
        );
    final _FreeNative free = library
        .lookupFunction<Void Function(Pointer<Utf16>), _FreeNative>(
          'DovetailFreeForwardedLaunch',
        );

    final Pointer<Int32> length = calloc<Int32>();
    try {
      final Pointer<Utf16> payload = take(length);
      if (payload == nullptr) {
        return null;
      }
      try {
        return decode(payload.toDartString(length: length.value));
      } finally {
        free(payload);
      }
    } finally {
      calloc.free(length);
    }
  }

  int _claimThrough(DynamicLibrary library, List<String> arguments) {
    final _ClaimNative claim = library
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Pointer<Utf16>>, Int32),
          _ClaimNative
        >('DovetailClaimPrimaryInstance');

    final Pointer<Utf16> key = instanceKey.toNativeUtf16();
    final Pointer<Pointer<Utf16>> passed = arguments.isEmpty
        ? nullptr
        : calloc<Pointer<Utf16>>(arguments.length);
    for (int index = 0; index < arguments.length; index++) {
      passed[index] = arguments[index].toNativeUtf16();
    }

    try {
      return claim(key, passed, arguments.length);
    } finally {
      for (int index = 0; index < arguments.length; index++) {
        calloc.free(passed[index]);
      }
      if (passed != nullptr) {
        calloc.free(passed);
      }
      calloc.free(key);
    }
  }

  static ForwardedLaunch decode(String payload) {
    final int split = payload.indexOf(_fieldSeparator);
    if (split < 0) {
      return ForwardedLaunch(
        workingDirectory: payload,
        arguments: const <String>[],
      );
    }
    final String rest = payload.substring(split + _fieldSeparator.length);
    return ForwardedLaunch(
      workingDirectory: payload.substring(0, split),
      arguments: rest.isEmpty
          ? const <String>[]
          : rest.split(_argumentSeparator),
    );
  }

  static DynamicLibrary? _open() {
    if (!Platform.isWindows) {
      return null;
    }
    try {
      return DynamicLibrary.open(_libraryName);
    } on Object {
      return null;
    }
  }
}
