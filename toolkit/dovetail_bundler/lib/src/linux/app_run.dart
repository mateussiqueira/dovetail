abstract final class AppRun {
  static const int mode = 0x1ED;

  static const String fileName = 'AppRun';

  static const String payloadDirectory = 'usr/bin';

  static String forBinary(String mainBinaryName) => <String>[
    '#!/bin/sh',
    'set -e',
    'here="\$(dirname "\$(readlink -f "\$0")")"',
    'exec "\$here/$payloadDirectory/$mainBinaryName" "\$@"',
    '',
  ].join('\n');
}
