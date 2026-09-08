import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/spec/bundle_spec.dart';

final class DesktopEntry {
  DesktopEntry({
    required this.appId,
    required this.name,
    required this.exec,
    this.comment,
    this.categories = const <String>['Network'],
    this.terminal = false,
    this.startupNotify = true,
    this.bundled = false,
  }) {
    if (!appId.contains('.')) {
      throw BundleFailure(
        'the desktop entry id "$appId" is not a reverse-domain name.',
        remedy:
            'A Wayland compositor matches the app id a process claims against '
            'the installed .desktop file name. A short name never matches, and '
            'the portal then refuses every request the app makes.',
      );
    }
    if (!bundled && !exec.startsWith('/')) {
      throw BundleFailure(
        'the desktop entry Exec is "$exec", which is not an absolute path.',
        remedy: 'A launcher does not search PATH the way a shell does.',
      );
    }
    if (bundled && exec.startsWith('/')) {
      throw BundleFailure(
        'the desktop entry Exec is "$exec", and it travels inside a bundle.',
        remedy:
            'An AppImage mounts itself somewhere under /tmp with a name it '
            'chooses at run time, so an absolute path here points at the '
            'user\'s own filesystem instead of at the app.',
      );
    }
  }

  factory DesktopEntry.forSpec(BundleSpec spec) => DesktopEntry(
    appId: spec.identifier,
    name: spec.productName,
    exec: '/usr/lib/${spec.mainBinaryName}/${spec.mainBinaryName}',
  );

  factory DesktopEntry.insideBundle(BundleSpec spec) => DesktopEntry(
    appId: spec.identifier,
    name: spec.productName,
    exec: spec.mainBinaryName,
    bundled: true,
  );

  final String appId;
  final String name;
  final String exec;
  final String? comment;
  final List<String> categories;
  final bool terminal;
  final bool startupNotify;
  final bool bundled;

  static const String installedDirectory = '/usr/share/applications';

  String get fileName => '$appId.desktop';

  String get installedPath => '$installedDirectory/$fileName';

  String render() => <String>[
    '[Desktop Entry]',
    'Type=Application',
    'Version=1.0',
    'Name=$name',
    if (comment != null && comment!.trim().isNotEmpty) 'Comment=$comment',
    'Exec=$exec',
    'Icon=$appId',
    'Terminal=$terminal',
    'Categories=${categories.join(';')};',
    'StartupNotify=$startupNotify',
    'StartupWMClass=$appId',
    '',
  ].join('\n');
}
