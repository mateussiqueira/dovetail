const String _afterExit =
    r'while kill -0 "$0" 2>/dev/null; do sleep 0.1; done; exec "$@"';
const String _bundleMarker = '.app/';

final class RelaunchCommand {
  const RelaunchCommand(this.executable, this.arguments);

  factory RelaunchCommand.forHost({
    required String operatingSystem,
    required String executable,
    required int pid,
    List<String> arguments = const <String>[],
    Map<String, String> environment = const <String, String>{},
  }) {
    final List<String> relaunched = operatingSystem == 'macos'
        ? _macosCommand(executable, arguments)
        : <String>[_linuxExecutable(executable, environment), ...arguments];
    return RelaunchCommand('/bin/sh', <String>[
      '-c',
      _afterExit,
      '$pid',
      ...relaunched,
    ]);
  }

  final String executable;
  final List<String> arguments;

  static List<String> _macosCommand(String executable, List<String> arguments) {
    final int marker = executable.indexOf(_bundleMarker);
    if (marker < 0) {
      return <String>[executable, ...arguments];
    }
    return <String>[
      '/usr/bin/open',
      '-n',
      executable.substring(0, marker + _bundleMarker.length - 1),
      if (arguments.isNotEmpty) ...<String>['--args', ...arguments],
    ];
  }

  static String _linuxExecutable(
    String executable,
    Map<String, String> environment,
  ) {
    final String appImage = environment['APPIMAGE'] ?? '';
    return appImage.isEmpty ? executable : appImage;
  }
}
