import 'dart:ffi';
import 'dart:io';

import 'package:dovetail_shortcut_channel/src/shortcut_refusal.dart';

abstract final class ShortcutLibrary {
  static const String stem = 'dovetail_shortcut_channel';

  static DynamicLibrary open({String? path}) {
    if (path != null) {
      return DynamicLibrary.open(path);
    }

    final List<String> candidates = _candidates();
    final List<String> refused = <String>[];
    for (final String candidate in candidates) {
      try {
        return DynamicLibrary.open(candidate);
      } on ArgumentError catch (error) {
        refused.add('$candidate: ${error.message}');
      }
    }

    throw ShortcutFailure(
      ShortcutRefusal.backendUnavailable,
      'the shortcut library loaded from none of the '
      '${candidates.length} names it is built under:\n  ${refused.join('\n  ')}',
    );
  }

  static List<String> _candidates() {
    if (Platform.isWindows) {
      return <String>['$stem.dll'];
    }
    if (Platform.isMacOS) {
      return <String>['$stem.framework/$stem', 'lib$stem.dylib'];
    }
    return <String>['lib$stem.so'];
  }
}
