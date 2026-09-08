import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/src/config/config_locator.dart';
import 'package:dovetail_cli/src/config/service_config.dart';
import 'package:dovetail_cli/src/command/doctor_command.dart';
import 'package:dovetail_cli/src/command/required_option.dart';

final class BundleCommand extends Command<int> {
  BundleCommand() {
    argParser
      ..addOption('target', allowed: knownTargets, help: 'defaults to the host')
      ..addOption(
        'product-name',
        help: 'the name a user sees in the installer and in Finder or Explorer',
      )
      ..addOption(
        'manufacturer',
        help:
            'the vendor string the MSI and the RPM require, and that Windows shows in Programs and Features',
      )
      ..addOption(
        'identifier',
        help:
            'reverse-dns id: CFBundleIdentifier on macOS, the upgrade code on Windows',
      )
      ..addOption(
        'version',
        help:
            'x.y.z; the bundlers refuse anything the target format cannot express',
      )
      ..addOption(
        'main-binary',
        help:
            'the executable inside the build output — usually the pubspec name',
      )
      ..addOption(
        'app-dir',
        help:
            'the directory flutter build produced, whose contents get wrapped',
      )
      ..addOption(
        'out-dir',
        help: 'where the installer lands; dist/ is what ship uses',
      )
      ..addOption('hooks')
      ..addOption('icon')
      ..addOption('license')
      ..addOption('homepage')
      ..addMultiOption(
        'arch',
        allowed: <String>['x86_64', 'arm64'],
        defaultsTo: <String>['x86_64'],
        help:
            'x86_64 covers every Intel and AMD desktop; they are one target. '
            'Give it twice on macOS to demand a universal bundle',
      )
      ..addMultiOption(
        'deb-depends',
        help: 'Debian package names, which are not the Fedora ones',
      )
      ..addFlag(
        'derive-depends',
        defaultsTo: true,
        help:
            'names the libraries the Flutter engine dlopens, and on a Debian '
            'host also asks dpkg-shlibdeps which packages own what the build '
            'links against',
      )
      ..addMultiOption(
        'rpm-requires',
        help: 'Fedora package names; gtk3 is what Debian calls libgtk-3-0',
      )
      ..addOption('root', help: 'the project directory; defaults to the cwd')
      ..addOption(
        'linux-format',
        allowed: <String>['both', 'deb', 'rpm', 'appimage'],
        defaultsTo: 'both',
        help:
            'a host with no rpmbuild asks for deb. appimage updates itself '
            'without asking for a password, and installs nothing — so it is '
            'refused when the config declares a service',
      )
      ..addOption(
        'appimage-runtime',
        help:
            'path to runtime-<arch> from the type2-runtime releases; an '
            'AppImage is that file with a squashfs appended, and this toolkit '
            'does not carry a copy of it',
      )
      ..addOption('mksquashfs', defaultsTo: 'mksquashfs')
      ..addOption('makensis', defaultsTo: 'makensis')
      ..addFlag(
        'nsis-unicode',
        defaultsTo: true,
        help:
            'off compiles where the Unicode stub crashes, and reads paths in '
            'the system code page',
      )
      ..addOption(
        'wixl',
        defaultsTo: 'wixl',
        help: 'builds the MSI on any host that is not Windows',
      )
      ..addOption(
        'windows-format',
        allowed: <String>['nsis', 'msi'],
        defaultsTo: 'nsis',
        help: 'nsis is the consumer channel; msi exists for MDM deployment',
      )
      ..addOption('upgrade-code', help: 'required by --windows-format msi')
      ..addOption(
        'macos-format',
        allowed: <String>['dmg', 'tar'],
        defaultsTo: 'dmg',
        help:
            'dmg for the download page; tar for the updater — the .app.tar.gz '
            'that installed clients extract and swap in place',
      )
      ..addOption('wix', defaultsTo: 'wix')
      ..addMultiOption(
        'conflicting-registry-key',
        help: 'an install by another installer of this product aborts the msi',
      )
      ..addOption('plugin-dir', defaultsTo: '')
      ..addOption(
        'install-mode',
        allowed: <String>['per-machine', 'current-user'],
        defaultsTo: 'per-machine',
      );
  }

  @override
  String get name => 'bundle';

  @override
  String get description =>
      'Produces an installer for one platform. Never signs anything.';

  @override
  Future<int> run() async {
    final ArgResults args = argResults!;
    final String target = args.option('target') ?? hostTarget();

    final BundleSpec spec = BundleSpec(
      productName: requiredOption(args, 'product-name', usage),
      manufacturer: requiredOption(args, 'manufacturer', usage),
      identifier: requiredOption(args, 'identifier', usage),
      version: AppVersion.parse(requiredOption(args, 'version', usage)),
      mainBinaryName: requiredOption(args, 'main-binary', usage),
      appDirectory: requiredOption(args, 'app-dir', usage),
      outputDirectory: requiredOption(args, 'out-dir', usage),
      installMode: args.option('install-mode') == 'current-user'
          ? InstallMode.currentUser
          : InstallMode.perMachine,
      installerHooks: args.option('hooks'),
      installerIcon: args.option('icon'),
      licenseFile: args.option('license'),
      homepage: args.option('homepage'),
    );

    final List<String> produced = switch (target) {
      'windows' => <String>[await _windows(spec, args)],
      'macos' => <String>[await _macos(spec, args)],
      'linux' => await _linux(spec, args),
      _ => throw UsageException('unknown target $target', usage),
    };

    produced.forEach(stdout.writeln);
    return 0;
  }

  Future<String> _windows(BundleSpec spec, ArgResults args) async {
    if (args.option('windows-format') == 'msi') {
      return _msi(spec, args);
    }

    final bool ours = args.option('plugin-dir')!.isEmpty;
    final Directory plugins = ours
        ? Directory.systemTemp.createTempSync('dovetail_plugins')
        : Directory(args.option('plugin-dir')!);

    try {
      return await NsisBundler(
        runner: const SystemProcessRunner(),
        makensis: args.option('makensis')!,
        pluginDirectory: plugins.path,
        arch: _singleArchitecture(args),
        unicode: args.flag('nsis-unicode'),
      ).bundle(spec);
    } finally {
      if (ours && plugins.existsSync()) {
        plugins.deleteSync(recursive: true);
      }
    }
  }

  Future<String> _macos(BundleSpec spec, ArgResults args) =>
      switch (args.option('macos-format')) {
        'tar' => AppArchiveBundler(
          runner: const SystemProcessRunner(),
          requiredArchitectures: _architectures(args),
        ).bundle(spec),
        _ => DmgBundler(
          runner: const SystemProcessRunner(),
          requiredArchitectures: _architectures(args),
        ).bundle(spec),
      };

  Set<TargetArch> _architectures(ArgResults args) =>
      args.multiOption('arch').map(TargetArch.parse).toSet();

  TargetArch _singleArchitecture(ArgResults args) {
    final Set<TargetArch> chosen = _architectures(args);
    if (chosen.length != 1) {
      throw UsageException(
        'this target takes one --arch, and ${chosen.length} were given.',
        'Only a macOS bundle can carry two architectures in one artefact. '
            'Windows and Linux packages are built once per architecture.\n\n'
            '$usage',
      );
    }
    return chosen.single;
  }

  Future<String> _msi(BundleSpec spec, ArgResults args) {
    final String? upgradeCode = args.option('upgrade-code');
    if (upgradeCode == null) {
      throw UsageException(
        '--windows-format msi needs --upgrade-code.',
        'It is the identity every future upgrade is matched against, so it is '
            'generated once for the product and then never changed. Losing it '
            'means shipping an installer that cannot upgrade what is already '
            'out there.\n\n$usage',
      );
    }

    return MsiBundler(
      tool: WixTool(
        runner: const SystemProcessRunner(),
        executable: args.option('wix')!,
      ),
      wixl: WixlTool(
        runner: const SystemProcessRunner(),
        executable: args.option('wixl')!,
      ),
    ).bundle(
      MsiSpec(
        bundle: spec,
        upgradeCode: upgradeCode,
        arch: _singleArchitecture(args),
        conflictingRegistryKeys: args.multiOption('conflicting-registry-key'),
      ),
    );
  }

  Future<List<String>> _debDependsFor(
    BundleSpec spec,
    List<String> declared,
  ) async => _union(
    _union(declared, FlutterRuntimeLibraries.debian),
    await const ShlibDeps(runner: SystemProcessRunner()).forBundle(spec),
  );

  IconSource? _iconOf(ArgResults args) {
    final String? path = args.option('icon');
    return path == null || path.trim().isEmpty ? null : IconSource.read(path);
  }

  static List<String> _union(List<String> declared, List<String> extra) {
    final Set<String> named = declared
        .map((String entry) => entry.split(' ').first)
        .toSet();
    return <String>[
      ...declared,
      ...extra.where((String entry) => !named.contains(entry.split(' ').first)),
    ];
  }

  Future<List<String>> _linux(BundleSpec spec, ArgResults args) async {
    final TargetArch arch = _singleArchitecture(args);
    final bool derive = args.flag('derive-depends');
    final List<String> depends = derive
        ? await _debDependsFor(spec, args.multiOption('deb-depends'))
        : args.multiOption('deb-depends');
    final List<String> requires = derive
        ? _union(args.multiOption('rpm-requires'), FlutterRuntimeLibraries.rpm)
        : args.multiOption('rpm-requires');
    // `from`, e nao o cwd: `Directory.current` pertence ao PROCESSO, e o
    // `dart test` roda cada suite como isolate de um processo so — uma suite
    // que o move muda o que todas as outras resolvem.
    final ServiceConfig? service = ConfigLocator.load(
      from: args.option('root'),
    )?.service;

    if (service != null) {
      stdout.writeln('service  ${service.unit.fileName}');
    }

    final String format = args.option('linux-format')!;

    if (format == 'appimage' && service != null) {
      // Um AppImage nao instala nada: ele executa de um arquivo. Sem instalar
      // nao ha unit systemd, sem a unit nao ha helper privilegiado, e sem o
      // helper nao ha kill switch. O que sai nao e produto degradado — e uma
      // janela que nao conecta, num formato que parecia ter sido construido
      // com sucesso.
      //
      // Este ramo passava direto: `unit`, `policy` e `scripts` chegam ao deb e
      // ao rpm e nao chegam aqui, entao o servico sumia em silencio. O README
      // ja dizia isso em prosa; dizer em prosa nao impede ninguem.
      throw UsageException(
        'this project declares a service (${service.unit.fileName}), and an '
            'AppImage cannot install one.',
        'An AppImage runs from a file instead of installing, so there is no '
            'systemd unit, no privileged helper, and no kill switch — and the '
            'three routes to privilege are closed, not hard: fusermount '
            'forces nosuid on the mount, --appimage-extract-and-run cannot '
            'chown to root, and asking for a password at runtime is refused '
            'by the product itself.\n\n'
            'Build deb and rpm instead (--linux-format both), whose postinst '
            'and %post install the unit and the polkit policy. If this '
            'product really has no privileged service, remove the service '
            'section from dovetail.yaml.\n\n$usage',
      );
    }

    if (format == 'appimage') {
      return <String>[
        await AppImageBundler(
          runner: const SystemProcessRunner(),
          arch: arch,
          runtimePath: args.option('appimage-runtime'),
          mksquashfs: args.option('mksquashfs')!,
          icon: _iconOf(args),
        ).bundle(spec),
      ];
    }

    return <String>[
      if (format != 'rpm')
        await DebBundler(
          arch: arch,
          depends: depends,
          unit: service?.unit,
          policy: service?.policy,
          scripts: service?.scripts,
        ).bundle(spec),
      if (format != 'deb')
        await RpmBundler(
          runner: const SystemProcessRunner(),
          arch: arch,
          requires: requires,
          unit: service?.unit,
          policy: service?.policy,
          scripts: service?.scripts,
        ).bundle(spec),
    ];
  }
}
