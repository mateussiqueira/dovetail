import 'package:flutter/foundation.dart';

const String _appBundleMarker = '.app/';
const String _appImageVariable = 'APPIMAGE';

final class ExecutablePath {
  const ExecutablePath({
    required this.platform,
    required this.resolvedExecutable,
    this.environment = const <String, String>{},
  });

  final TargetPlatform platform;
  final String resolvedExecutable;
  final Map<String, String> environment;

  String forLoginItem() {
    if (platform == TargetPlatform.macOS) {
      return _bundleOrExecutable();
    }
    if (platform == TargetPlatform.linux) {
      return _appImageOrExecutable();
    }
    return resolvedExecutable;
  }

  String _bundleOrExecutable() {
    final int marker = resolvedExecutable.indexOf(_appBundleMarker);
    if (marker < 0) {
      return resolvedExecutable;
    }
    return resolvedExecutable.substring(
      0,
      marker + _appBundleMarker.length - 1,
    );
  }

  String _appImageOrExecutable() {
    final String? mounted = environment[_appImageVariable];
    if (mounted == null || mounted.isEmpty) {
      return resolvedExecutable;
    }
    return mounted;
  }
}
