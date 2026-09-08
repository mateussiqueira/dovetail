import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/spec/app_version.dart';

abstract final class MsiVersion {
  static const int fieldCeiling = 255;
  static const int buildCeiling = 65535;

  static String of(AppVersion version) {
    _refuseOutOfRange('major', version.major, fieldCeiling);
    _refuseOutOfRange('minor', version.minor, fieldCeiling);
    _refuseOutOfRange('patch', version.patch, buildCeiling);
    return '${version.major}.${version.minor}.${version.patch}';
  }

  static bool comparesEqual(AppVersion a, AppVersion b) =>
      a.major == b.major && a.minor == b.minor && a.patch == b.patch;

  static void _refuseOutOfRange(String field, int value, int ceiling) {
    if (value > ceiling) {
      throw BundleFailure(
        'Version field $field is $value, above the MSI ceiling of $ceiling.',
        remedy:
            'Windows Installer compares only major.minor.patch, and it stores '
            'major and minor in one byte each and patch in two. A version '
            'above the ceiling produces an installer that cannot recognise '
            'its own upgrade.',
      );
    }
  }
}
