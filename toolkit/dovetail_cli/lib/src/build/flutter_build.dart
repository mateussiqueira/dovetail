import 'package:dovetail_cli/src/config/config_failure.dart';

final class FlutterBuild {
  const FlutterBuild._();

  static const Map<String, String> hostFor = <String, String>{
    'macos': 'macos',
    'windows': 'windows',
    'linux': 'linux',
  };

  static const Map<String, String> outputFor = <String, String>{
    'macos': 'build/macos/Build/Products/Release',
    'windows': 'build/windows/x64/runner/Release',
    'linux': 'build/linux/x64/release/bundle',
  };

  static List<String> argumentsFor(
    String target, {
    bool release = true,
    Map<String, String> defines = const <String, String>{},
    List<String> extra = const <String>[],
  }) => <String>[
    'build',
    target,
    if (release) '--release' else '--debug',
    for (final MapEntry<String, String> define in defines.entries)
      '--dart-define=${define.key}=${define.value}',
    ...extra,
  ];

  static void refuseCrossCompile(String target, String host) {
    if (target == host) {
      return;
    }
    throw ConfigFailure(
      'a $target build needs a $target machine, and this is $host.',
      remedy:
          'Flutter refuses it at the source: "build $target" only supported '
          'on ${_capitalised(target)} hosts. Signing and packaging can be '
          'centralised on one machine; compiling cannot, so the pipeline '
          'needs a runner per operating system for this step and only this '
          'step.',
    );
  }

  static String _capitalised(String target) => target == 'macos'
      ? 'macOS'
      : target[0].toUpperCase() + target.substring(1);
}
