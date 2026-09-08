import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2 ||
      (arguments[0] == 'appimage' && arguments.length < 3)) {
    stderr.writeln(
      'usage: install_probe package <path>\n'
      '       install_probe appimage <new path> <installed path>',
    );
    exit(2);
  }

  final String path = arguments[1];
  final VerifiedArtifact artifact = VerifiedArtifact.trusted(
    bytes: Uint8List.fromList(File(path).readAsBytesSync()),
    sourceUrl: 'https://cdn.example/${p.basename(path)}',
    trustedComment: 'install probe',
  );

  final LinuxInstaller installer = LinuxInstaller(
    runner: const SystemProcessRunner(),
    appImagePath: arguments[0] == 'appimage' ? arguments[2] : '/nonexistent',
    scratchDirectory: p.join(Directory.systemTemp.path, 'dovetail_probe'),
  );

  stdout.writeln('privileged=${installer.alreadyPrivileged()}');
  try {
    final InstallOutcome outcome = await installer.install(artifact);
    stdout.writeln('outcome=${outcome.name}');
  } on UpdateFailure catch (failure) {
    stdout.writeln('failure=${failure.message}');
    stdout.writeln('remedy=${failure.remedy}');
    exit(1);
  }
}
