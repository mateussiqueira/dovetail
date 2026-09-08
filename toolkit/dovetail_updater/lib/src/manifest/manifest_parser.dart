import 'dart:convert';

import 'package:dovetail_updater/src/manifest/platform_release.dart';
import 'package:dovetail_updater/src/manifest/update_manifest.dart';
import 'package:dovetail_updater/src/update_failure.dart';
import 'package:pub_semver/pub_semver.dart';

abstract final class ManifestParser {
  static UpdateManifest parse(String body, {String? platformKey}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw UpdateFailure('the manifest is not valid JSON: ${error.message}');
    }

    if (decoded is! Map<String, Object?>) {
      throw const UpdateFailure('the manifest is not a JSON object.');
    }

    final Version version = _version(decoded);
    final Object? platforms = decoded['platforms'];

    if (platforms == null) {
      if (platformKey == null) {
        throw const UpdateFailure(
          'this manifest has no platforms map, so it answers for one platform '
          'only, and no platform key was given to file it under.',
        );
      }
      return UpdateManifest(
        version: version,
        releases: <String, PlatformRelease>{
          platformKey: _release(decoded, platformKey),
        },
        notes: decoded['notes']?.toString(),
        publishedAt: _publishedAt(decoded),
      );
    }

    if (platforms is! Map<String, Object?>) {
      throw const UpdateFailure('platforms is not a JSON object.');
    }
    if (platforms.isEmpty) {
      throw const UpdateFailure('platforms is empty.');
    }

    final Map<String, PlatformRelease> releases = <String, PlatformRelease>{};
    for (final MapEntry<String, Object?> entry in platforms.entries) {
      final Object? value = entry.value;
      if (value is! Map<String, Object?>) {
        throw UpdateFailure('the ${entry.key} block is not a JSON object.');
      }
      releases[entry.key] = _release(value, entry.key);
    }

    return UpdateManifest(
      version: version,
      releases: releases,
      notes: decoded['notes']?.toString(),
      publishedAt: _publishedAt(decoded),
    );
  }

  static Version _version(Map<String, Object?> json) {
    final Object? raw = json['version'] ?? json['name'];
    if (raw == null) {
      throw const UpdateFailure('the manifest has no version.');
    }
    final String text = raw.toString().trim();
    try {
      return Version.parse(text.startsWith('v') ? text.substring(1) : text);
    } on FormatException {
      throw UpdateFailure('"$text" is not a semantic version.');
    }
  }

  static PlatformRelease _release(Map<String, Object?> json, String where) {
    final Object? url = json['url'];
    final Object? signature = json['signature'];

    if (url == null || url.toString().trim().isEmpty) {
      throw UpdateFailure('$where has no url.');
    }
    if (signature == null || signature.toString().trim().isEmpty) {
      throw UpdateFailure('$where has no signature.');
    }

    final String signatureText = signature.toString().trim();
    if (_looksLikeReference(signatureText)) {
      throw UpdateFailure(
        '$where carries a path or a URL where the signature belongs.',
        remedy:
            'The field holds the content of the .sig file, not a reference to '
            'it. A path here is silently unverifiable.',
      );
    }

    return PlatformRelease(url: url.toString(), signature: signatureText);
  }

  static bool _looksLikeReference(String value) {
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return true;
    }
    if (value.startsWith('/') && !value.contains('\n')) {
      return true;
    }
    if (value.endsWith('.sig') || value.endsWith('.minisig')) {
      return true;
    }
    return value.startsWith('file://');
  }

  static final RegExp _dateFields = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

  static DateTime? _publishedAt(Map<String, Object?> json) {
    final Object? raw = json['pub_date'];
    if (raw == null) {
      return null;
    }
    final String text = raw.toString().trim();
    final DateTime? parsed = DateTime.tryParse(text);
    if (parsed == null) {
      throw UpdateFailure(
        'the manifest carries a pub_date of "$text", which is not a date.',
        remedy:
            'A date the client cannot read used to be treated as no date at '
            'all, so a typo silently removed the publication time.',
      );
    }
    if (!_roundTrips(text, parsed)) {
      throw UpdateFailure(
        'the pub_date "$text" is not the date it names.',
        remedy:
            'DateTime rolls a month of 13 or an hour of 99 forward instead of '
            'refusing, so an out-of-range field becomes a plausible date '
            'months away from the one that was written.',
      );
    }
    return parsed;
  }

  static bool _roundTrips(String text, DateTime parsed) {
    final RegExpMatch? fields = _dateFields.firstMatch(text);
    if (fields == null) {
      return true;
    }
    final DateTime asWritten = parsed.isUtc ? parsed.toUtc() : parsed;
    return int.parse(fields.group(1)!) == asWritten.year &&
        int.parse(fields.group(2)!) == asWritten.month &&
        int.parse(fields.group(3)!) == asWritten.day;
  }
}
