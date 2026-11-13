import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/src/doctor/tool_executable.dart';
import 'package:dovetail_cli/src/doctor/tool_probe.dart';

final class RustTargetProbe implements ToolProbe {
  const RustTargetProbe({
    required this.os,
    required this.arch,
    this.rustup = 'rustup',
  });

  final TargetOs os;
  final TargetArch arch;
  final String rustup;

  String get triple => arch.rustTriple(os);

  @override
  String get name => triple;

  @override
  String get purpose => 'lets cargo build the core for this target';

  @override
  Future<ToolReport> probe() async {
    final String? resolved = findToolExecutable(rustup);
    if (resolved == null) {
      return ToolReport(
        name: name,
        purpose: purpose,
        status: ToolStatus.absent,
      );
    }
    final ProcessResult installed;
    try {
      installed = Process.runSync(resolved, <String>[
        'target',
        'list',
        '--installed',
      ]);
    } on ProcessException catch (error) {
      return ToolReport(
        name: name,
        purpose: purpose,
        status: ToolStatus.unusable,
        detail: error.message,
      );
    }

    if (installed.exitCode != 0) {
      return ToolReport(
        name: name,
        purpose: purpose,
        status: ToolStatus.unusable,
        detail: installed.stderr.toString().trim(),
      );
    }

    final Set<String> targets = installed.stdout
        .toString()
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toSet();

    if (targets.contains(triple)) {
      return ToolReport(
        name: name,
        purpose: purpose,
        status: ToolStatus.usable,
        path: 'installed',
      );
    }

    return ToolReport(
      name: name,
      purpose: purpose,
      status: ToolStatus.absent,
      detail: 'rustup target add $triple',
    );
  }
}
