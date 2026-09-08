import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
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
    final ProcessResult installed;
    try {
      installed = Process.runSync(rustup, <String>[
        'target',
        'list',
        '--installed',
      ]);
    } on ProcessException {
      return ToolReport(
        name: name,
        purpose: purpose,
        status: ToolStatus.absent,
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
