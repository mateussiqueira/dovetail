import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/icon/hicolor_icons.dart';
import 'package:dovetail_bundler/src/icon/icon_source.dart';
import 'package:dovetail_bundler/src/linux/desktop_entry.dart';
import 'package:dovetail_bundler/src/linux/polkit_policy.dart';
import 'package:dovetail_bundler/src/linux/service_scripts.dart';
import 'package:dovetail_bundler/src/linux/systemd_unit.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:dovetail_bundler/src/spec/bundle_spec.dart';
import 'package:dovetail_bundler/src/spec/staged_file.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:path/path.dart' as p;

final class RpmBundler {
  const RpmBundler({
    required this.runner,
    this.rpmbuild = 'rpmbuild',
    this.arch = TargetArch.x86_64,
    this.requires = const <String>[],
    this.release = '1',
    this.unit,
    this.policy,
    this.scripts,
    this.icon,
  });

  final ProcessRunner runner;
  final String rpmbuild;
  final TargetArch arch;
  final List<String> requires;
  final String release;
  final SystemdUnit? unit;
  final PolkitPolicy? policy;
  final ServiceScripts? scripts;
  final IconSource? icon;

  String get architecture => arch.rpm;

  void _refuseHalfConfiguredService() {
    if (unit == null && scripts == null) {
      return;
    }
    if (unit == null || scripts == null) {
      throw const BundleFailure(
        'a unit without scriptlets, or scriptlets without a unit.',
        remedy:
            'The %systemd_post macro enables a unit the package has to have '
            'installed. Give both or neither.',
      );
    }
    if (scripts!.unitFileName != unit!.fileName) {
      throw BundleFailure(
        'the scriptlets name "${scripts!.unitFileName}" but the package '
        'installs "${unit!.fileName}".',
        remedy: 'They have to name the same file.',
      );
    }
  }

  String fileNameFor(BundleSpec spec) =>
      '${spec.mainBinaryName}-${spec.version.semantic}-$release'
      '.$architecture.rpm';

  String specFileFor(BundleSpec spec) {
    final StringBuffer out = StringBuffer()
      ..writeln('Name: ${spec.mainBinaryName}')
      ..writeln('Version: ${spec.version.semantic}')
      ..writeln('Release: $release')
      ..writeln('Summary: ${spec.productName}')
      ..writeln('License: proprietary')
      ..writeln('BuildArch: $architecture')
      ..writeln('Vendor: ${spec.manufacturer}');

    if (spec.homepage != null) {
      out.writeln('URL: ${spec.homepage}');
    }
    for (final String requirement in requires) {
      out.writeln('Requires: $requirement');
    }
    if (unit != null) {
      out
        ..writeln('BuildRequires: systemd-rpm-macros')
        ..writeln(r'%{?systemd_requires}');
    }
    if (policy != null) {
      out.writeln('Requires: polkit');
    }

    out
      ..writeln('%global _build_id_links none')
      ..writeln('%global __os_install_post %{nil}')
      ..writeln()
      ..writeln('%description')
      ..writeln(spec.productName)
      ..writeln()
      ..writeln('%files')
      ..writeln('/usr/lib/${spec.mainBinaryName}')
      ..writeln(DesktopEntry.forSpec(spec).installedPath);

    if (icon != null) {
      out.writeln('${HicolorIcons.themeRoot}/*/apps/${spec.identifier}.png');
    }

    if (unit != null) {
      out.writeln(unit!.installedPath);
    }
    if (policy != null) {
      out.writeln(policy!.installedPath);
    }
    for (final StagedFile staged in spec.extraFiles) {
      out.writeln(
        staged.destination.startsWith('/')
            ? staged.destination
            : '/${staged.destination}',
      );
    }

    if (scripts != null) {
      out
        ..writeln()
        ..writeln('%post')
        ..writeln(scripts!.rpmPost)
        ..writeln()
        ..writeln('%preun')
        ..writeln(scripts!.rpmPreun)
        ..writeln()
        ..writeln('%postun')
        ..writeln(scripts!.rpmPostun);
    }

    return out.toString();
  }

  void _stage(String buildRoot, String installedPath, String content) {
    final File file = File(
      p.join(buildRoot, installedPath.replaceFirst('/', '')),
    )..parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  static const String _probedUnit = 'dovetail-probe.service';

  Future<ProcessOutcome> _run(List<String> arguments) async {
    try {
      return await runner.run(rpmbuild, arguments);
    } on ProcessException catch (error) {
      throw BundleFailure(
        'there is no $rpmbuild on this host, so no rpm is built here.',
        remedy:
            'Fedora calls the package rpm-build, Debian and Homebrew call it '
            'rpm. A host that only ships Debian packages asks for '
            '--linux-format deb instead of installing it. (${error.message})',
      );
    }
  }

  Future<void> _refuseWithoutSystemdMacros() async {
    if (unit == null) {
      return;
    }

    final ProcessOutcome probe = await _run(<String>[
      '--eval',
      '%systemd_post $_probedUnit',
    ]);
    if (!probe.stdout.trim().startsWith('%')) {
      return;
    }

    throw const BundleFailure(
      'this host has no systemd rpm macros, and the package declares a '
      'service.',
      remedy:
          'The spec expands %systemd_post, %systemd_preun and '
          '%systemd_postun_with_restart, which the systemd-rpm-macros package '
          'defines. There is no such package for macOS, so an rpm that '
          'installs a unit is built on a Linux host — a container is enough. '
          'An rpm with no service builds here.',
    );
  }

  Future<String> bundle(BundleSpec spec) async {
    final Directory app = Directory(spec.appDirectory);
    if (!app.existsSync()) {
      throw BundleFailure(
        'the built application is not at ${spec.appDirectory}.',
        remedy: 'Run flutter build linux --release first.',
      );
    }
    _refuseHalfConfiguredService();
    await _refuseWithoutSystemdMacros();

    final Directory output = Directory(spec.outputDirectory)
      ..createSync(recursive: true);
    final Directory stage = Directory(p.join(output.path, 'rpm'))
      ..createSync(recursive: true);

    final Directory buildRoot = Directory(p.join(stage.path, 'buildroot'));
    if (buildRoot.existsSync()) {
      buildRoot.deleteSync(recursive: true);
    }
    final Directory installTo = Directory(
      p.join(buildRoot.path, 'usr', 'lib', spec.mainBinaryName),
    )..createSync(recursive: true);

    final ProcessOutcome copied = await runner.run('cp', <String>[
      '-R',
      '${app.absolute.path}/.',
      installTo.path,
    ]);
    if (!copied.succeeded) {
      throw BundleFailure(
        'could not stage the application into the buildroot.',
        remedy: copied.firstDiagnostic,
      );
    }

    final bool staged = installTo
        .listSync(recursive: true)
        .whereType<File>()
        .isNotEmpty;
    if (!staged) {
      throw BundleFailure(
        '${spec.appDirectory} has no files to package.',
        remedy:
            'cp reported success and copied nothing, so rpmbuild would build '
            'a package that installs an empty directory.',
      );
    }

    final DesktopEntry entry = DesktopEntry.forSpec(spec);
    _stage(buildRoot.path, entry.installedPath, entry.render());
    if (unit != null) {
      _stage(buildRoot.path, unit!.installedPath, unit!.render());
    }
    if (policy != null) {
      _stage(buildRoot.path, policy!.installedPath, policy!.render());
    }
    for (final StagedFile staged in spec.extraFiles) {
      final File source = File(staged.source);
      if (!source.existsSync()) {
        throw BundleFailure(
          'the staged file ${staged.source} does not exist.',
          remedy:
              'A package that silently drops a staged file installs an '
              'application missing the piece it was staged for.',
        );
      }
      final File destination = File(
        p.join(
          buildRoot.path,
          staged.destination.replaceFirst(RegExp('^/+'), ''),
        ),
      )..parent.createSync(recursive: true);
      source.copySync(destination.path);
      Process.runSync('chmod', <String>[
        (source.statSync().mode & 0x1FF).toRadixString(8).padLeft(3, '0'),
        destination.path,
      ]);
    }
    if (icon != null) {
      for (final HicolorIcon themed in HicolorIcons.fromSource(
        source: icon!,
        appId: spec.identifier,
      )) {
        final File file = File(
          p.join(buildRoot.path, themed.installedPath.replaceFirst('/', '')),
        )..parent.createSync(recursive: true);
        file.writeAsBytesSync(themed.png);
      }
    }

    final File specFile = File(
      p.join(stage.path, '${spec.mainBinaryName}.spec'),
    )..writeAsStringSync(specFileFor(spec));

    final ProcessOutcome built = await _run(<String>[
      '-bb',
      '--target',
      architecture,
      '--define',
      '_topdir ${stage.absolute.path}',
      '--define',
      '_rpmdir ${output.absolute.path}',
      '--define',
      '_rpmfilename ${fileNameFor(spec)}',
      '--buildroot',
      buildRoot.absolute.path,
      specFile.path,
    ]);

    if (!built.succeeded) {
      throw BundleFailure(
        'rpmbuild failed with exit code ${built.exitCode}.',
        remedy: built.stderr.trim().isEmpty
            ? built.stdout.trim()
            : built.stderr.trim(),
      );
    }

    final String destination = p.join(output.path, fileNameFor(spec));
    if (!File(destination).existsSync()) {
      throw BundleFailure(
        'rpmbuild reported success but ${fileNameFor(spec)} is not there.',
      );
    }

    return destination;
  }
}
