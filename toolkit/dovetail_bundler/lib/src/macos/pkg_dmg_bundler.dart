import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/macos/dmg_bundler.dart';
import 'package:dovetail_bundler/src/macos/launch_daemon.dart';
import 'package:dovetail_bundler/src/macos/pkg_bundler.dart';
import 'package:dovetail_bundler/src/macos/service_scripts.dart';
import 'package:dovetail_bundler/src/spec/bundle_spec.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:path/path.dart' as p;

final class PkgDmgBundler {
  const PkgDmgBundler({
    required this.runner,
    this.instructions,
    this.pkgbuild = 'pkgbuild',
    this.productbuild = 'productbuild',
    this.hdiutil = 'hdiutil',
    this.requiredArchitectures = const <TargetArch>{},
    this.daemon,
    this.scripts,
  });

  final ProcessRunner runner;
  final String? instructions;
  final String pkgbuild;
  final String productbuild;
  final String hdiutil;
  final Set<TargetArch> requiredArchitectures;
  final LaunchDaemon? daemon;
  final MacosServiceScripts? scripts;

  String fileNameFor(BundleSpec spec) {
    final String pkg = PkgBundler(
      runner: runner,
      requiredArchitectures: requiredArchitectures,
    ).fileNameFor(spec);
    return '${pkg.substring(0, pkg.length - '.pkg'.length)}.dmg';
  }

  Future<String> bundle(BundleSpec spec) async {
    final String? text = instructions?.trim();
    if (text == null || text.isEmpty) {
      throw const BundleFailure(
        'a pkg inside a dmg needs the text a person reads before installing.',
        remedy:
            'Declare service.macos.instructions in dovetail.yaml, pointing at '
            'the instructions file. The dmg carries the .pkg and the text, and '
            'the text is the application own.',
      );
    }
    final File instructionsFile = File(text);
    if (!instructionsFile.existsSync()) {
      throw BundleFailure(
        'the instructions file is not at $text.',
        remedy: 'Point service.macos.instructions at a file that exists.',
      );
    }

    final String pkg = await PkgBundler(
      runner: runner,
      pkgbuild: pkgbuild,
      productbuild: productbuild,
      requiredArchitectures: requiredArchitectures,
      daemon: daemon,
      scripts: scripts,
    ).bundle(spec);

    final Directory stage = Directory.systemTemp.createTempSync(
      'dovetail_pkgdmg',
    );
    try {
      final String pkgName = p.basename(pkg);
      File(
        p.join(stage.path, pkgName),
      ).writeAsBytesSync(File(pkg).readAsBytesSync());
      File(p.join(stage.path, p.basename(text))).writeAsStringSync(
        instructionsFile.readAsStringSync().replaceAll('@PKG@', pkgName),
      );

      return await DmgBundler(runner: runner, hdiutil: hdiutil).bundleFrom(
        spec: spec,
        source: stage.path,
        destination: p.join(spec.outputDirectory, fileNameFor(spec)),
      );
    } finally {
      stage.deleteSync(recursive: true);
    }
  }
}
