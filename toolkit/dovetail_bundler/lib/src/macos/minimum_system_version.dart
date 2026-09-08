import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:path/path.dart' as p;

/// The oldest macOS a bundle admits to needing.
///
/// `LSMinimumSystemVersion` is the only thing that stops an old Mac from
/// launching a binary it cannot run. Without it the app opens and then dies
/// on a missing symbol, which reaches us as "it just closes" and reaches the
/// person using it as nothing at all.
///
/// Xcode fills the key from `MACOSX_DEPLOYMENT_TARGET`, so a correct project
/// already has one — this exists for the day somebody edits the template, and
/// for the release that declares one floor while the bundle carries another.
final class MinimumSystemVersion {
  const MinimumSystemVersion._();

  /// Matches the `<string>` that follows the key. The plist Xcode writes is
  /// XML and stays XML (`PLIST_FILE_OUTPUT_FORMAT` defaults to
  /// same-as-input), so this reads the file rather than shelling out to
  /// plutil and dragging a process into a pure function. A binary plist is
  /// refused by name instead of parsed as garbage.
  static final RegExp _entry = RegExp(
    r'<key>\s*LSMinimumSystemVersion\s*</key>\s*<string>([^<]*)</string>',
  );

  static File plistOf(String bundlePath) =>
      File(p.join(bundlePath, 'Contents', 'Info.plist'));

  /// What the bundle says, or null when the key is absent.
  static String? readFrom(String bundlePath) {
    final File plist = plistOf(bundlePath);
    if (!plist.existsSync()) {
      throw BundleFailure(
        'no Info.plist inside $bundlePath.',
        remedy:
            'Every .app has one at Contents/Info.plist. A bundle without it '
            'is not a bundle macOS will open.',
      );
    }

    final String text = plist.readAsStringSync();
    if (text.startsWith('bplist00')) {
      throw BundleFailure(
        'the Info.plist in $bundlePath is a binary plist.',
        remedy:
            'Convert it and try again: plutil -convert xml1 '
            '"${plist.path}". Xcode writes XML by default, so a binary one '
            'means something in the project changed '
            'PLIST_FILE_OUTPUT_FORMAT.',
      );
    }

    final RegExpMatch? match = _entry.firstMatch(text);
    final String? found = match?.group(1)?.trim();
    return found == null || found.isEmpty ? null : found;
  }

  /// Refuses a bundle that names no floor, or one that disagrees with what
  /// the release declares.
  static String enforce({required String bundlePath, String? declared}) {
    final String? found = readFrom(bundlePath);
    if (found == null) {
      throw BundleFailure(
        'the bundle at $bundlePath declares no LSMinimumSystemVersion.',
        remedy:
            'Set MACOSX_DEPLOYMENT_TARGET in the macOS project and let the '
            'Info.plist template read it as \$(MACOSX_DEPLOYMENT_TARGET). '
            'Without the key an old Mac launches the app and then it dies on '
            'a missing symbol.',
      );
    }
    // Unsubstituted: Xcode did not expand the variable, which means the
    // bundle carries the literal text and macOS reads no version at all.
    if (found.contains(r'$(')) {
      throw BundleFailure(
        'the bundle at $bundlePath carries "$found" as its minimum system '
        'version.',
        remedy:
            'That is the build setting, unexpanded. macOS reads it as no '
            'version at all. Build through Xcode rather than copying the '
            'template.',
      );
    }
    if (declared != null && declared.trim() != found) {
      throw BundleFailure(
        'the release declares macOS ${declared.trim()} and the bundle '
        'carries $found.',
        remedy:
            'One of the two is wrong, and the bundle is what the operating '
            'system obeys. Either fix MACOSX_DEPLOYMENT_TARGET or fix '
            'minimum-system-version in the config.',
      );
    }
    return found;
  }
}
