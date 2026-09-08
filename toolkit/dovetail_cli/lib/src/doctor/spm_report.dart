import 'dart:io';

import 'package:dovetail_cli/src/config/pubspec_version.dart';
import 'package:dovetail_cli/src/doctor/project_report.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:path/path.dart' as p;

/// O que o doctor sabe dos plugins Rust que o SPM resolve — no macOS os
/// plugins entram por Swift Package Manager, e o `Package.swift` de cada um
/// carrega um binaryTarget: o `.xcframework` que `tool/build_xcframework.sh`
/// constrói. Esse artefato NÃO é versionado (o `.gitignore` exclui, e o repo
/// guarda só o script), então quem mudou Rust e esqueceu de reconstruir só
/// descobre no build — o doctor diz antes. `ok`/`off`, nunca `missing`: o
/// `.xcframework` é o artefato do macOS/SPM, e a falta dele não quebra quem
/// fica no CocoaPods (o cargokit reconstrói o dylib dentro do build do Xcode).
final class SpmReport {
  const SpmReport(this.notes);

  final List<ProjectNote> notes;

  static SpmReport of({required SdkInstall? sdk, required String home}) {
    if (sdk == null) {
      return const SpmReport(<ProjectNote>[
        ProjectNote(
          subject: 'install',
          finding: ProjectFinding.notConfigured,
          detail: 'no SDK — dovetail self-install',
        ),
      ]);
    }

    final List<String> plugins = sdk
        .packages()
        .where(
          (String name) => File(
            p.join(sdk.packagesDir, name, 'macos', name, 'Package.swift'),
          ).existsSync(),
        )
        .toList();

    if (plugins.isEmpty) {
      return const SpmReport(<ProjectNote>[
        ProjectNote(
          subject: 'plugins',
          finding: ProjectFinding.notConfigured,
          detail: 'no Rust plugin in the SDK — nothing to build',
        ),
      ]);
    }

    return SpmReport(<ProjectNote>[
      for (final String name in plugins) _noteFor(sdk, name),
    ]);
  }

  static ProjectNote _noteFor(SdkInstall sdk, String name) {
    final Directory xcframework = Directory(
      p.join(sdk.packagesDir, name, 'macos', name, '$name.xcframework'),
    );

    if (!xcframework.existsSync()) {
      return ProjectNote(
        subject: name,
        finding: ProjectFinding.notConfigured,
        detail: '.xcframework missing — tool/build_xcframework.sh',
      );
    }

    return ProjectNote(
      subject: name,
      finding: ProjectFinding.ready,
      detail: _versionOf(sdk, name),
    );
  }

  static String _versionOf(SdkInstall sdk, String name) {
    try {
      return PubspecVersion.read(p.join(sdk.packagesDir, name));
    } on Object {
      return sdk.version;
    }
  }
}
