import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/windows/msi_component_tree.dart';
import 'package:dovetail_bundler/src/windows/msi_spec.dart';
import 'package:dovetail_bundler/src/windows/msi_backend.dart';
import 'package:dovetail_bundler/src/windows/wix_source.dart';
import 'package:dovetail_bundler/src/windows/wix_tool.dart';
import 'package:dovetail_bundler/src/windows/wixl_source.dart';
import 'package:dovetail_bundler/src/windows/wixl_tool.dart';
import 'package:path/path.dart' as p;

final class MsiBundler {
  const MsiBundler({this.tool, this.wixl, this._backend});

  final WixTool? tool;
  final WixlTool? wixl;
  final MsiBackend? _backend;

  MsiBackend get backend => _backend ?? MsiBackend.forHost();

  MsiComponentTree scan(MsiSpec spec) => MsiComponentTree.scan(
    appDirectory: spec.bundle.appDirectory,
    upgradeCode: spec.upgradeCode,
    extraFiles: spec.bundle.extraFiles,
  );

  String writeSource(MsiSpec spec) {
    final MsiComponentTree tree = scan(spec);
    final Directory output = Directory(spec.bundle.outputDirectory)
      ..createSync(recursive: true);
    final String sourceFile = p.join(
      output.path,
      '${spec.bundle.mainBinaryName}.wxs',
    );
    File(sourceFile).writeAsStringSync(
      backend == MsiBackend.wix
          ? WixSource.render(spec, tree)
          : WixlSource.render(spec, tree),
    );
    return sourceFile;
  }

  Future<String> bundle(MsiSpec spec) async {
    if (backend.needsWindows && !Platform.isWindows) {
      throw const BundleFailure(
        'the WiX toolset builds an MSI only on Windows.',
        remedy:
            'It binds through msi.dll, a Windows system library, so there is '
            'no cross-build with it. wixl writes the database directly and '
            'runs anywhere; MsiBackend.forHost picks it off Windows.',
      );
    }

    final String sourceFile = writeSource(spec);
    final String outputFile = p.join(
      spec.bundle.outputDirectory,
      spec.msiFileName,
    );

    await (backend == MsiBackend.wix
        ? _buildWithWix(spec, sourceFile, outputFile)
        : _buildWithWixl(spec, sourceFile, outputFile));

    if (!File(outputFile).existsSync()) {
      throw BundleFailure(
        '${backend.executable} reported success but $outputFile is not there.',
        remedy: 'Treat a missing artefact as a failed build, never as a pass.',
      );
    }
    return outputFile;
  }

  Future<void> _buildWithWix(
    MsiSpec spec,
    String sourceFile,
    String outputFile,
  ) async {
    final WixTool? wix = tool;
    if (wix == null) {
      throw const BundleFailure('no WixTool was given for the wix backend.');
    }
    await wix.build(
      sourceFile: sourceFile,
      outputFile: outputFile,
      arch: spec.arch,
      cultures: spec.cultures,
      defines: <String, String>{
        'StageDir': p.normalize(spec.bundle.appDirectory),
      },
    );
  }

  Future<void> _buildWithWixl(
    MsiSpec spec,
    String sourceFile,
    String outputFile,
  ) async {
    final WixlTool? tool = wixl;
    if (tool == null) {
      throw const BundleFailure('no WixlTool was given for the wixl backend.');
    }
    await tool.build(
      sourceFile: sourceFile,
      outputFile: outputFile,
      arch: spec.arch,
    );
  }
}
