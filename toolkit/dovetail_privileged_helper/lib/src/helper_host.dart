import 'dart:io';

/// The operating system a helper is being asked about.
///
/// Taken as a value rather than read from `Platform` at every call, so a test
/// can describe any host from any machine — the same reason the shortcut
/// channel next door takes its host as a value.
enum HelperHost {
  windows,
  macos,
  linux,

  /// Anything else: a phone, a browser, a host added after this was written.
  other;

  /// The host this process is running on.
  static HelperHost current() {
    if (Platform.isWindows) {
      return HelperHost.windows;
    }
    if (Platform.isMacOS) {
      return HelperHost.macos;
    }
    if (Platform.isLinux) {
      return HelperHost.linux;
    }
    return HelperHost.other;
  }
}
