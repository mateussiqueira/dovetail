import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/src/doctor/rust_target_probe.dart';
import 'package:dovetail_cli/src/doctor/tool_probe.dart';
import 'package:path/path.dart' as p;

final class CommandProbe implements ToolProbe {
  const CommandProbe({
    required this.name,
    required this.purpose,
    required this.trivialArguments,
    this.inputFiles = const <String, String>{},
    this.expectsFile,
    this.identity,
    this.acceptsNonZeroExit = false,
  });

  @override
  final String name;

  @override
  final String purpose;

  final List<String> trivialArguments;
  final Map<String, String> inputFiles;
  final String? expectsFile;
  final Pattern? identity;
  final bool acceptsNonZeroExit;

  @override
  Future<ToolReport> probe() async {
    final String? resolved = _which(name);
    if (resolved == null) {
      return ToolReport(
        name: name,
        purpose: purpose,
        status: ToolStatus.absent,
      );
    }

    final Directory scratch = Directory.systemTemp.createTempSync(
      'dovetail_probe',
    );
    try {
      for (final MapEntry<String, String> file in inputFiles.entries) {
        File(p.join(scratch.path, file.key)).writeAsStringSync(file.value);
      }

      final ProcessResult attempt = Process.runSync(
        resolved,
        trivialArguments,
        workingDirectory: scratch.path,
      );

      final Pattern? expected = identity;
      if (expected != null) {
        final String spoke = '${attempt.stdout}\n${attempt.stderr}';
        if (!spoke.contains(expected)) {
          return ToolReport(
            name: name,
            purpose: purpose,
            status: ToolStatus.impostor,
            path: resolved,
            detail:
                '$resolved is ${_selfDescription(spoke)}, not the tool this '
                'step needs',
          );
        }
      }

      final bool produced =
          expectsFile == null ||
          File(p.join(scratch.path, expectsFile!)).existsSync();

      if ((attempt.exitCode == 0 || acceptsNonZeroExit) && produced) {
        return ToolReport(
          name: name,
          purpose: purpose,
          status: ToolStatus.usable,
          path: resolved,
        );
      }

      return ToolReport(
        name: name,
        purpose: purpose,
        status: ToolStatus.unusable,
        path: resolved,
        detail: _firstLine(attempt),
      );
    } on ProcessException catch (error) {
      return ToolReport(
        name: name,
        purpose: purpose,
        status: ToolStatus.unusable,
        path: resolved,
        detail: error.message,
      );
    } finally {
      scratch.deleteSync(recursive: true);
    }
  }

  static String _selfDescription(String spoke) {
    final List<String> lines = spoke
        .trim()
        .split('\n')
        .where((String line) => line.trim().isNotEmpty)
        .toList();
    return lines.isEmpty
        ? 'a program that says nothing about itself'
        : '"${lines.first.trim()}"';
  }

  String _firstLine(ProcessResult result) {
    final String text = result.stderr.toString().trim().isEmpty
        ? result.stdout.toString()
        : result.stderr.toString();
    final List<String> lines = text
        .trim()
        .split('\n')
        .where((String line) => line.trim().isNotEmpty)
        .toList();
    return lines.isEmpty ? 'exit code ${result.exitCode}' : lines.first.trim();
  }

  static String? _which(String name) {
    final ProcessResult found = Process.runSync(
      Platform.isWindows ? 'where' : 'which',
      <String>[name],
    );
    if (found.exitCode != 0) {
      return null;
    }
    final String output = found.stdout.toString().trim();
    return output.isEmpty ? null : output.split('\n').first.trim();
  }
}

/// The probe that answers the question the NSIS step really asks: can this
/// host compile the installer the bundler generates? It renders the real
/// script for a minimal payload and runs makensis with the exact flags and
/// environment the bundler passes, then checks the artifact exists. A
/// trivial script is not the artifact, and a probe built on one reports
/// "ok" for a toolchain that aborts on the real thing.
final class NsisProbe implements ToolProbe {
  const NsisProbe();

  @override
  String get name => 'makensis';

  @override
  String get purpose => 'compiles the NSIS installer';

  @override
  Future<ToolReport> probe() async {
    final String? resolved = _which(name);
    if (resolved == null) {
      return ToolReport(
        name: name,
        purpose: purpose,
        status: ToolStatus.absent,
      );
    }

    final Directory scratch = Directory.systemTemp.createTempSync(
      'dovetail_probe',
    );
    try {
      final String appDir = p.join(scratch.path, 'app');
      Directory(appDir).createSync();
      final Directory plugins = Directory(p.join(scratch.path, 'plugins'))
        ..createSync();
      final BundleSpec spec = BundleSpec(
        productName: 'DovetailProbe',
        manufacturer: 'Dovetail',
        identifier: 'com.example.probe',
        version: AppVersion.parse('0.0.1'),
        mainBinaryName: 'probe',
        appDirectory: appDir,
        outputDirectory: p.join(scratch.path, 'out'),
      );
      File(
        p.join(scratch.path, 'dovetail_utils.nsh'),
      ).writeAsStringSync(NsisUtils.source);
      File(
        p.join(scratch.path, 'installer.nsi'),
      ).writeAsStringSync(NsisScript.render(spec, TargetArch.x86_64));

      final ProcessResult attempt = Process.runSync(
        resolved,
        <String>[
          '-INPUTCHARSET',
          'UTF8',
          '-OUTPUTCHARSET',
          'UTF8',
          '-V2',
          '-DPLUGINDIR=${plugins.path}',
          'installer.nsi',
        ],
        workingDirectory: scratch.path,
        environment: <String, String>{'DOVETAIL_APP_DIR': appDir},
      );

      final String produced = p.join(
        scratch.path,
        spec.installerFileNameFor(TargetArch.x86_64),
      );
      if (attempt.exitCode == 0 && File(produced).existsSync()) {
        return ToolReport(
          name: name,
          purpose: purpose,
          status: ToolStatus.usable,
          path: resolved,
        );
      }
      return ToolReport(
        name: name,
        purpose: purpose,
        status: ToolStatus.unusable,
        path: resolved,
        detail: _detail(attempt),
      );
    } on ProcessException catch (error) {
      return ToolReport(
        name: name,
        purpose: purpose,
        status: ToolStatus.unusable,
        path: resolved,
        detail: error.message,
      );
    } finally {
      scratch.deleteSync(recursive: true);
    }
  }

  static String? _which(String name) {
    final ProcessResult found = Process.runSync(
      Platform.isWindows ? 'where' : 'which',
      <String>[name],
    );
    if (found.exitCode != 0) {
      return null;
    }
    final String output = found.stdout.toString().trim();
    return output.isEmpty ? null : output.split('\n').first.trim();
  }

  static String _detail(ProcessResult result) {
    final String text = result.stderr.toString().trim().isEmpty
        ? result.stdout.toString()
        : result.stderr.toString();
    final List<String> lines = text
        .trim()
        .split('\n')
        .where((String line) => line.trim().isNotEmpty)
        .toList();
    return lines.isEmpty ? 'exit code ${result.exitCode}' : lines.first.trim();
  }
}

abstract final class Doctor {
  static const Set<String> _known = <String>{'windows', 'macos', 'linux'};

  static List<ToolProbe> probesFor(
    String platform, {
    TargetArch? arch,
    String rustup = 'rustup',
  }) => <ToolProbe>[
    if (_known.contains(platform)) ...<ToolProbe>[
      if (arch != null)
        RustTargetProbe(os: _osFor(platform), arch: arch, rustup: rustup),
      ..._toolsFor(platform),
      ..._everyTarget,
    ],
  ];

  static const List<ToolProbe> _everyTarget = <ToolProbe>[
    CommandProbe(
      name: 'minisign',
      purpose: 'signs the update artefact, on whichever runner builds it',
      trivialArguments: <String>['-v'],
    ),
  ];

  static TargetOs _osFor(String platform) => switch (platform) {
    'windows' => TargetOs.windows,
    'macos' => TargetOs.macos,
    _ => TargetOs.linux,
  };

  static List<ToolProbe> _toolsFor(String platform) => switch (platform) {
    'windows' => <ToolProbe>[
      // The probe compiles the REAL generated installer, not a four-line
      // script: on this machine the trivial script compiles while the real
      // one aborts writing the Unicode stub, and a probe that answers
      // "usable" for a host that cannot build the actual artifact is the
      // false positive this doctor exists to kill.
      const NsisProbe(),
      // The bundler asks MsiBackend.forHost which binary it will invoke, and
      // this has to ask the same question. It used to probe `wix`
      // unconditionally, so on this machine — where wixl is installed and
      // builds a real MSI — doctor reported `missing wix` and refused a
      // target the host can actually deliver. Worse than the false negative:
      // the tool that WOULD be invoked was never probed at all, so a wixl
      // that is present and broken passed unseen until the bundle failed.
      if (MsiBackend.forHost().needsWindows)
        const CommandProbe(
          name: 'wix',
          purpose: 'compiles the MSI on Windows, through msi.dll',
          trivialArguments: <String>['--version'],
        )
      else
        const CommandProbe(
          name: 'wixl',
          purpose: 'compiles the MSI without a Windows machine',
          trivialArguments: <String>['--version'],
        ),
      if (Platform.isWindows)
        const CommandProbe(
          name: 'signtool',
          purpose: 'signs the binaries and the installer',
          trivialArguments: <String>['/?'],
          identity: 'Authenticode',
        )
      else
        const CommandProbe(
          name: 'osslsigncode',
          purpose: 'signs the Windows binaries without a Windows machine',
          trivialArguments: <String>['--version'],
          identity: 'osslsigncode',
          acceptsNonZeroExit: true,
        ),
    ],
    'macos' => <ToolProbe>[
      const CommandProbe(
        name: 'hdiutil',
        purpose: 'builds the dmg',
        trivialArguments: <String>['help'],
      ),
      const CommandProbe(
        name: 'codesign',
        purpose: 'signs the app bundle',
        trivialArguments: <String>['-dv', '/bin/ls'],
      ),
      const CommandProbe(
        name: 'xcrun',
        purpose: 'reaches notarytool and stapler',
        trivialArguments: <String>['--find', 'notarytool'],
      ),
      const CommandProbe(
        name: 'lipo',
        purpose: 'merges the two slices of a universal bundle',
        trivialArguments: <String>['-archs', '/bin/ls'],
      ),
      const CommandProbe(
        name: 'ditto',
        purpose: 'archives the bundle for the notary service',
        trivialArguments: <String>['source.txt', 'copy.txt'],
        inputFiles: <String, String>{'source.txt': 'probe'},
        expectsFile: 'copy.txt',
      ),
    ],
    'linux' => <ToolProbe>[
      const CommandProbe(
        name: 'rpmbuild',
        purpose: 'builds the rpm',
        trivialArguments: <String>['--version'],
      ),
      const CommandProbe(
        name: 'shasum',
        purpose: 'writes SHA256SUMS',
        trivialArguments: <String>['--version'],
      ),
    ],
    _ => const <ToolProbe>[],
  };

  static Future<List<ToolReport>> run(List<ToolProbe> probes) async {
    final List<ToolReport> reports = <ToolReport>[];
    for (final ToolProbe probe in probes) {
      reports.add(await probe.probe());
    }
    return reports;
  }

  static String render(List<ToolReport> reports) {
    if (reports.isEmpty) {
      return 'no probe is defined for this target.';
    }
    return reports.map((ToolReport report) => report.line).join('\n');
  }

  static bool allUsable(List<ToolReport> reports) =>
      reports.isNotEmpty && reports.every((ToolReport r) => r.isUsable);
}
