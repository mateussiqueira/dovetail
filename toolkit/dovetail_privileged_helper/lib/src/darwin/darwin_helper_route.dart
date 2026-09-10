/// The two ways macOS lets an application own a privileged component.
///
/// The fork is real and this toolkit refuses to pick for its users, because
/// the two answers are not better and worse — they are two different products.
/// `ARCHITECTURE.md` carries the full comparison; the short of it is below.
enum DarwinHelperRoute {
  /// A root daemon registered with `SMAppService`, the default.
  ///
  /// Ships outside the App Store, needs no entitlement anyone has to grant,
  /// and the user approves it once in Login Items. In exchange the app can
  /// never be listed on the Mac App Store, and it carries a root process it
  /// is responsible for.
  privilegedDaemon,

  /// A Network Extension, **not implemented**.
  ///
  /// The only route onto the Mac App Store, and the one that produces the
  /// prompt people recognise. It costs an entitlement Apple grants by
  /// application, on its own timetable, so a package cannot promise it. Ask
  /// for it here and the selector answers with an unsupported helper that
  /// says so, rather than quietly installing a daemon the caller did not
  /// choose.
  networkExtension,
}
