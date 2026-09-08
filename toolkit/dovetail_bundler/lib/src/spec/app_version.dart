import 'package:dovetail_bundler/src/bundle_failure.dart';

final class AppVersion {
  const AppVersion._(this.major, this.minor, this.patch, this.build);

  factory AppVersion.parse(String raw) {
    final String trimmed = raw.trim();
    final RegExpMatch? match = _pattern.firstMatch(trimmed);
    if (match == null) {
      throw BundleFailure(
        'Version "$raw" is not major.minor.patch with an optional numeric build.',
        remedy: 'Write it as 1.2.3 or 1.2.3+4.',
      );
    }

    final String? build = match.group(4);
    if (build != null && !_digits.hasMatch(build)) {
      throw BundleFailure(
        'Version "$raw" carries non-numeric build metadata "$build".',
        remedy:
            'Windows accepts only unsigned decimal numbers in a file version. '
            'A sign or a 0x prefix parses as an integer and writes a version '
            'no installer reads back the way it was meant.',
      );
    }

    return AppVersion._(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      build == null ? 0 : int.parse(build),
    );
  }

  static final RegExp _pattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(.+))?$');
  static final RegExp _digits = RegExp(r'^[0-9]+$');

  final int major;
  final int minor;
  final int patch;
  final int build;

  String get semantic => '$major.$minor.$patch';

  String get windowsFileVersion => '$major.$minor.$patch.$build';

  @override
  String toString() => build == 0 ? semantic : '$semantic+$build';
}
