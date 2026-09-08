import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:path/path.dart' as p;
import 'package:dovetail_cli/src/command/required_option.dart';

final class ManifestCommand extends Command<int> {
  ManifestCommand() {
    argParser
      ..addOption(
        'version',
        help: 'the version this manifest announces to installed clients',
      )
      ..addOption('notes')
      ..addOption('out', defaultsTo: 'latest.json')
      ..addMultiOption(
        'release',
        help: 'platformKey=url=path/to/.sig ; repeatable',
      );
  }

  @override
  String get name => 'manifest';

  @override
  String get description =>
      'Writes the update manifest, embedding the content of each signature.';

  @override
  Future<int> run() async {
    final ArgResults args = argResults!;
    final List<String> releases = args.multiOption('release');
    if (releases.isEmpty) {
      throw UsageException('at least one --release is needed', usage);
    }

    final List<ManifestEntry> entries = <ManifestEntry>[];
    for (final String release in releases) {
      final List<String> parts = release.split('=');
      if (parts.length != 3) {
        throw UsageException(
          'expected platformKey=url=signaturePath, got "$release"',
          usage,
        );
      }

      final File signature = File(parts[2]);
      if (!signature.existsSync()) {
        throw UsageException('no signature file at ${parts[2]}', usage);
      }

      entries.add(
        ManifestEntry(
          platformKey: parts[0],
          url: parts[1],
          // Not trimmed: the manifest carries the .minisig byte for byte, and
          // ManifestWriter is what decides the encoding on the way out.
          signature: signature.readAsStringSync(),
        ),
      );
    }

    final String destination = args.option('out')!;
    Directory(p.dirname(destination)).createSync(recursive: true);
    File(destination).writeAsStringSync(
      ManifestWriter.render(
        version: requiredOption(args, 'version', usage),
        notes: args.option('notes'),
        entries: entries,
      ),
    );

    stdout.writeln(destination);
    return 0;
  }
}
