import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/src/inspect/artifact_inspection.dart';
import 'package:path/path.dart' as p;

final class ArtifactInspector {
  const ArtifactInspector({this.codesign = 'codesign'});

  final String codesign;

  ArtifactInspection inspect(String path) {
    final ArtifactKind kind = kindOf(path);
    return switch (kind) {
      ArtifactKind.macosBundle => _bundle(path),
      ArtifactKind.machO => _machO(path),
      _ => ArtifactInspection(
        path: path,
        kind: kind,
        declaredArchitecture: architectureInName(path),
        notes: const <String>[
          'this inspector reads macOS bundles and Mach-O files; for a '
              '.deb, .rpm, .msi or .exe it only read the name',
        ],
      ),
    };
  }

  ArtifactInspection _bundle(String path) {
    final BundleArchitectureReport report = BundleArchitectures.inspect(
      bundlePath: path,
      required_: const <TargetArch>{},
    );

    final Set<TargetArch> everywhere = report.carriedByAll;
    final Set<TargetArch> anywhere = report.binaries
        .expand((BundleBinary binary) => binary.info.architectures)
        .toSet();

    return ArtifactInspection(
      path: path,
      kind: ArtifactKind.macosBundle,
      architectures: everywhere,
      declaredArchitecture: architectureInName(path),
      signature: _signatureOf(path),
      notes: <String>[
        '${report.binaries.length} Mach-O files',
        if (anywhere.length > everywhere.length)
          'some binaries carry ${anywhere.map((TargetArch a) => a.apple).join(', ')} '
              'but not all of them do, so this bundle is universal only in '
              'part and will not launch on every Mac it installs on',
      ],
    );
  }

  ArtifactInspection _machO(String path) {
    final MachOInfo info = MachO.read(path);
    return ArtifactInspection(
      path: path,
      kind: ArtifactKind.machO,
      architectures: info.architectures,
      declaredArchitecture: architectureInName(path),
      signature: _signatureOf(path),
      notes: <String>[
        info.kind == MachOKind.fat ? 'fat header' : 'thin header',
        if (info.unknownCpuTypes.isNotEmpty)
          'carries cpu types this bundler has no name for: '
              '${info.unknownCpuTypes.map((int t) => '0x${t.toRadixString(16)}').join(', ')}',
      ],
    );
  }

  String? _signatureOf(String path) {
    if (!Platform.isMacOS) {
      return null;
    }
    final ProcessResult verified = Process.runSync(codesign, <String>[
      '--verify',
      '--deep',
      '--strict',
      path,
    ]);
    if (verified.exitCode == 0) {
      return 'valid';
    }
    final String reason = verified.stderr.toString().trim();
    return reason.contains('not signed')
        ? 'absent'
        : 'invalid: ${reason.split('\n').first}';
  }

  static ArtifactKind kindOf(String path) {
    final String extension = p.extension(path).toLowerCase();
    for (final ArtifactKind kind in ArtifactKind.values) {
      if (kind.extension.isNotEmpty && kind.extension == extension) {
        return kind;
      }
    }
    if (Directory(path).existsSync()) {
      return ArtifactKind.unknown;
    }
    return MachO.read(path).isMachO ? ArtifactKind.machO : ArtifactKind.unknown;
  }

  static TargetArch? architectureInName(String path) {
    final String name = p.basename(path).toLowerCase();
    if (name.contains('universal')) {
      return null;
    }
    for (final String token in <String>[
      'aarch64',
      'arm64',
      'x86_64',
      'amd64',
      'x64',
    ]) {
      if (name.contains(token)) {
        return TargetArch.parse(token);
      }
    }
    return null;
  }
}
