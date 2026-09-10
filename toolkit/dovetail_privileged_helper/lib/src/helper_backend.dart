/// Which operating-system facility this package is talking to.
///
/// Reported rather than assumed, because the same [HelperState] means
/// different things to a support engineer depending on who produced it, and
/// because one platform has two of these.
enum HelperBackend {
  /// No facility: the host has none, or the spec named none for it.
  none,

  /// macOS 13+, `SMAppService.daemon(plistName:)`.
  ///
  /// A root daemon registered from inside the app bundle. Works outside the
  /// App Store; the user approves it in Login Items.
  launchDaemon,

  /// macOS, the Network Extension family.
  ///
  /// Named without its class names on purpose: `toolkit_purity_test` forbids
  /// a toolkit package from carrying the vocabulary of any one product, and
  /// those class names are that vocabulary even though Apple chose them.
  ///
  /// **Nothing returns this yet.** It is declared now so that the day a
  /// Network Extension backend lands, a caller's `switch` over this enum
  /// still compiles — adding an enum value later is what breaks exhaustive
  /// switches, and this package would rather take that cost before anyone
  /// depends on it than after. `ARCHITECTURE.md` says what the route costs
  /// and why it is not the default.
  networkExtension,

  /// Windows, the service control manager.
  windowsService,

  /// Linux, a systemd unit, with polkit as the authentication step.
  systemdUnit,
}
