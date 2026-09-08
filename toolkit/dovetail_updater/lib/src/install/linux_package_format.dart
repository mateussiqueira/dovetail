import 'package:dovetail_updater/src/update_failure.dart';
import 'package:path/path.dart' as p;

enum LinuxPackageFormat {
  appImage('.appimage'),
  debian('.deb'),
  rpm('.rpm');

  const LinuxPackageFormat(this.extension);

  final String extension;

  bool get needsPrivilege => this != LinuxPackageFormat.appImage;

  static LinuxPackageFormat of(String fileName) {
    final String extension = p.extension(fileName).toLowerCase();
    for (final LinuxPackageFormat format in values) {
      if (format.extension == extension) {
        return format;
      }
    }

    throw UpdateFailure(
      'the artefact is "$fileName", which is not a package this can apply.',
      remedy:
          'Publish one of ${values.map((LinuxPackageFormat format) => format.extension).join(', ')} '
          'as the Linux update artefact. An AppImage replaces itself; a .deb '
          'or .rpm is handed to the system package manager, which asks for '
          'authorisation.',
    );
  }
}
