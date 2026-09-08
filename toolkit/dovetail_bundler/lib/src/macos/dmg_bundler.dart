import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/macos/bundle_architectures.dart';
import 'package:dovetail_bundler/src/macos/minimum_system_version.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:dovetail_bundler/src/spec/bundle_spec.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:path/path.dart' as p;

final class DmgBundler {
  const DmgBundler({
    required this.runner,
    this.hdiutil = 'hdiutil',
    this.requiredArchitectures = const <TargetArch>{},
  });

  final ProcessRunner runner;
  final String hdiutil;
  final Set<TargetArch> requiredArchitectures;

  List<String> argumentsFor(BundleSpec spec, String destination) => <String>[
    'create',
    '-volname',
    spec.productName,
    '-srcfolder',
    spec.appDirectory,
    '-ov',
    '-format',
    'UDZO',
    destination,
  ];

  String fileNameFor(BundleSpec spec) {
    final String suffix = switch (requiredArchitectures.length) {
      0 => '',
      1 => '_${requiredArchitectures.single.apple}',
      _ => '_universal',
    };
    return '${spec.mainBinaryName}_${spec.version.semantic}$suffix.dmg';
  }

  Future<String> bundle(BundleSpec spec) async {
    final Directory app = Directory(spec.appDirectory);
    if (!app.existsSync()) {
      throw BundleFailure(
        'the built application is not at ${spec.appDirectory}.',
        remedy: 'Run flutter build macos --release first.',
      );
    }
    if (p.extension(spec.appDirectory) != '.app') {
      throw BundleFailure(
        '${spec.appDirectory} is not an .app bundle.',
        remedy:
            'A dmg wraps the bundle, not the directory above it. Point '
            'app-dir at the .app itself.',
      );
    }

    if (spec.extraFiles.isNotEmpty) {
      throw BundleFailure(
        'a dmg was given ${spec.extraFiles.length} staged file(s), and a dmg '
        'has nowhere to put them.',
        remedy:
            'A dmg wraps the .app. Anything the application needs belongs '
            'inside the bundle before it is wrapped and before it is signed, '
            'because the bundle seal covers it.',
      );
    }

    if (requiredArchitectures.isNotEmpty) {
      BundleArchitectures.enforce(
        bundlePath: spec.appDirectory,
        required_: requiredArchitectures,
      );
    }

    // Before hdiutil, not after: a dmg that exists is a dmg somebody uploads,
    // and the floor it carries is the only thing that stops an old Mac from
    // launching a binary it cannot run.
    MinimumSystemVersion.enforce(
      bundlePath: spec.appDirectory,
      declared: spec.minimumSystemVersion,
    );

    Directory(spec.outputDirectory).createSync(recursive: true);
    final String destination = p.join(spec.outputDirectory, fileNameFor(spec));

    final ProcessOutcome outcome = await runner.run(
      hdiutil,
      argumentsFor(spec, destination),
    );
    if (!outcome.succeeded) {
      throw BundleFailure(
        'hdiutil failed with exit code ${outcome.exitCode}.',
        remedy: outcome.stderr.trim().isEmpty
            ? outcome.stdout.trim()
            : outcome.stderr.trim(),
      );
    }

    if (!File(destination).existsSync()) {
      throw BundleFailure(
        'hdiutil reported success but ${fileNameFor(spec)} is not there.',
      );
    }

    return destination;
  }
}
