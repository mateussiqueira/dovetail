import 'package:pub_semver/pub_semver.dart';

final class DowngradeRefused implements Exception {
  const DowngradeRefused({required this.offered, required this.installed});

  final Version offered;
  final Version installed;

  String get message =>
      'the manifest offers $offered while $installed is installed.';

  String get remedy =>
      'A downgrade is refused here rather than left to a client side '
      'comparison, because the signature alone does not prevent one: any '
      'older artefact signed with the same key would verify.';

  @override
  String toString() => '$message\n  $remedy';
}
