import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _QueryNative =
    Int32 Function(Pointer<Utf8> name, Pointer<Int32> startType);
typedef _QueryDart = int Function(Pointer<Utf8> name, Pointer<Int32> startType);

typedef _CreateNative =
    Int32 Function(
      Pointer<Utf8> name,
      Pointer<Utf8> displayName,
      Pointer<Utf8> imagePath,
    );
typedef _CreateDart =
    int Function(
      Pointer<Utf8> name,
      Pointer<Utf8> displayName,
      Pointer<Utf8> imagePath,
    );

typedef _DeleteNative = Int32 Function(Pointer<Utf8> name);
typedef _DeleteDart = int Function(Pointer<Utf8> name);

/// What one query of the control manager returned.
typedef WindowsServiceReading = ({int error, int startType});

/// The three calls this package makes into the service control manager.
///
/// Symbols are resolved when this is built, not on each call, so
/// [isAvailable] can answer honestly. The appearance probe next door learned
/// that the hard way: on some hosts opening the library always succeeds, and a
/// check that asked only "did it open?" reported itself available and found
/// out otherwise at the first call.
final class WindowsServiceControl {
  /// The control this host offers, or an absent one where the DLL is not.
  factory WindowsServiceControl({DynamicLibrary? library}) {
    final DynamicLibrary? opened = library ?? _open();
    if (opened == null) {
      return const WindowsServiceControl.absent();
    }
    try {
      return WindowsServiceControl._(
        opened.lookupFunction<_QueryNative, _QueryDart>(
          'DovetailWindowsServiceQuery',
        ),
        opened.lookupFunction<_CreateNative, _CreateDart>(
          'DovetailWindowsServiceCreate',
        ),
        opened.lookupFunction<_DeleteNative, _DeleteDart>(
          'DovetailWindowsServiceDelete',
        ),
      );
    } on ArgumentError {
      // The DLL is there and a symbol is not: an application built against an
      // older version of this package. "Not available" is the honest answer,
      // and it is not the same as "Windows cannot do this".
      return const WindowsServiceControl.absent();
    }
  }

  const WindowsServiceControl._(this._query, this._create, this._delete);

  /// A control with nothing behind it, for tests and for hosts without the
  /// DLL.
  const WindowsServiceControl.absent()
    : _query = null,
      _create = null,
      _delete = null;

  final _QueryDart? _query;
  final _CreateDart? _create;
  final _DeleteDart? _delete;

  /// Whether there is a control manager to talk to.
  bool get isAvailable => _query != null;

  /// The start type of [name], with the Win32 error that reading it produced.
  ///
  /// `ERROR_INVALID_FUNCTION` stands in when there is no native side: a code
  /// the control manager itself never returns for this call, so a caller
  /// cannot mistake it for something Windows said.
  WindowsServiceReading query(String name) {
    final _QueryDart? ask = _query;
    if (ask == null) {
      return (error: _noNative, startType: 0);
    }
    final Pointer<Int32> startType = calloc<Int32>();
    final Pointer<Utf8> nativeName = name.toNativeUtf8();
    try {
      final int error = ask(nativeName, startType);
      return (error: error, startType: startType.value);
    } finally {
      calloc.free(startType);
      malloc.free(nativeName);
    }
  }

  /// Creates the service, returning the Win32 error — zero for success.
  int create({
    required String name,
    required String displayName,
    required String imagePath,
  }) {
    final _CreateDart? make = _create;
    if (make == null) {
      return _noNative;
    }
    final Pointer<Utf8> nativeName = name.toNativeUtf8();
    final Pointer<Utf8> nativeDisplay = displayName.toNativeUtf8();
    final Pointer<Utf8> nativeImage = imagePath.toNativeUtf8();
    try {
      return make(nativeName, nativeDisplay, nativeImage);
    } finally {
      malloc.free(nativeName);
      malloc.free(nativeDisplay);
      malloc.free(nativeImage);
    }
  }

  /// Deletes the service, returning the Win32 error — zero for success.
  int delete(String name) {
    final _DeleteDart? remove = _delete;
    if (remove == null) {
      return _noNative;
    }
    final Pointer<Utf8> nativeName = name.toNativeUtf8();
    try {
      return remove(nativeName);
    } finally {
      malloc.free(nativeName);
    }
  }

  /// `ERROR_INVALID_FUNCTION`.
  static const int _noNative = 1;

  static DynamicLibrary? _open() {
    if (!Platform.isWindows) {
      return null;
    }
    try {
      return DynamicLibrary.open('dovetail_privileged_helper.dll');
    } on Object {
      return null;
    }
  }
}
