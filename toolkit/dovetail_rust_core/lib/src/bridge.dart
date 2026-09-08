import 'package:flutter/foundation.dart';

/// The three platforms a native desktop library is built for.
const Set<TargetPlatform> desktopPlatforms = <TargetPlatform>{
  TargetPlatform.windows,
  TargetPlatform.macOS,
  TargetPlatform.linux,
};

/// The two mobile platforms, for a bridge that ships a mobile library too.
const Set<TargetPlatform> mobilePlatforms = <TargetPlatform>{
  TargetPlatform.android,
  TargetPlatform.iOS,
};

/// Thrown by [RustBridge.ensureInitialized] where no native library exists
/// for the running platform.
///
/// The guard to write is [RustBridge.isSupported]; this is what happens
/// when the guard was not written.
class UnsupportedPlatformException implements Exception {
  /// The web has no native library at all.
  const UnsupportedPlatformException.web() : platform = null;

  /// A native platform this bridge was not built for.
  const UnsupportedPlatformException.platform(this.platform);

  /// The platform that was refused, or `null` on the web.
  final TargetPlatform? platform;

  @override
  String toString() {
    final String target = platform?.name ?? 'web';
    return 'UnsupportedPlatformException: no native library is built for '
        '$target. Guard the call with isSupported.';
  }
}

/// Loads a Rust library exactly once and says on which platforms it exists.
///
/// The [initializer] is the generated `RustLib.init`; calling
/// [ensureInitialized] from several places is the normal case, and the
/// second call awaits the first instead of loading twice. A failed load
/// is forgotten so the next call retries rather than replaying the error.
class RustBridge {
  /// A bridge over [initializer], available on [supportedPlatforms] and,
  /// when [supportsWeb], on the web.
  RustBridge({
    required this.initializer,
    this.supportedPlatforms = desktopPlatforms,
    this.supportsWeb = false,
  });

  /// Loads the native library; run at most once.
  final Future<void> Function() initializer;

  /// Where a native library is built; [desktopPlatforms] by default.
  final Set<TargetPlatform> supportedPlatforms;

  /// Whether a web build of the library exists.
  final bool supportsWeb;

  Future<void>? _initialization;

  /// Whether this platform has a library to load. Check before calling
  /// anything native; the alternative is [UnsupportedPlatformException].
  bool get isSupported =>
      kIsWeb ? supportsWeb : supportedPlatforms.contains(defaultTargetPlatform);

  /// Loads the library if it is not loaded yet, joining a load already in
  /// progress. Throws [UnsupportedPlatformException] where none exists.
  Future<void> ensureInitialized() async {
    if (kIsWeb && !supportsWeb) {
      throw const UnsupportedPlatformException.web();
    }
    if (!kIsWeb && !supportedPlatforms.contains(defaultTargetPlatform)) {
      throw UnsupportedPlatformException.platform(defaultTargetPlatform);
    }

    final Future<void>? pending = _initialization;
    if (pending != null) {
      return pending;
    }

    final Future<void> started = initializer();
    _initialization = started;
    return started.catchError((Object error, StackTrace stackTrace) {
      _initialization = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  @visibleForTesting
  /// Whether a load has started and not failed. For tests.
  bool get isInitialized => _initialization != null;
}
