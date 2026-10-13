import 'dart:convert';

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
    if (operatingSystem == 'windows') {
      return RelaunchCommand('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        _encoded(_windowsScript(pid, executable, arguments)),
      ]);
    }
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

  static String _windowsScript(
    int pid,
    String executable,
    List<String> arguments,
  ) {
    final String start = 'Start-Process -FilePath ${_quoted(executable)}';
    final String line = arguments.map(_windowsArgument).join(' ');
    return 'Wait-Process -Id $pid -ErrorAction SilentlyContinue; '
        '${arguments.isEmpty ? start : '$start -ArgumentList ${_quoted(line)}'}';
  }

  static String _quoted(String value) => "'${value.replaceAll("'", "''")}'";

  static String _windowsArgument(String argument) {
    if (argument.isNotEmpty && !argument.contains(RegExp(r'[\s"]'))) {
      return argument;
    }
    final StringBuffer quoted = StringBuffer('"');
    int backslashes = 0;
    for (final String character in argument.split('')) {
      if (character == r'\') {
        backslashes++;
        continue;
      }
      final int escapes = character == '"' ? backslashes * 2 + 1 : backslashes;
      quoted.write('${r'\' * escapes}$character');
      backslashes = 0;
    }
    quoted.write('${r'\' * (backslashes * 2)}"');
    return quoted.toString();
  }

  static String _encoded(String script) => base64.encode(<int>[
    for (final int unit in script.codeUnits) ...<int>[unit & 0xff, unit >> 8],
  ]);
}
