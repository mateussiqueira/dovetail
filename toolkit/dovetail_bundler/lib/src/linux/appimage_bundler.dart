import 'dart:io';
import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/icon/hicolor_icons.dart';
import 'package:dovetail_bundler/src/icon/icon_source.dart';
import 'package:dovetail_bundler/src/linux/app_run.dart';
import 'package:dovetail_bundler/src/linux/appended_image.dart';
import 'package:dovetail_bundler/src/linux/desktop_entry.dart';
import 'package:dovetail_bundler/src/linux/elf_header.dart';
import 'package:dovetail_bundler/src/spec/bundle_spec.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:path/path.dart' as p;
import 'package:dovetail_process_runner/dovetail_process_runner.dart';

final class AppImageBundler {
  const AppImageBundler({
    required this.runner,
    required this.arch,
    this.runtimePath,
    this.mksquashfs = 'mksquashfs',
    this.icon,
  });

  final ProcessRunner runner;
  final TargetArch arch;
  final String? runtimePath;
  final String mksquashfs;
  final IconSource? icon;

  static const String _runtimeSource =
      'https://github.com/AppImage/type2-runtime/releases';

  String get architecture => arch.appImage;

  String fileNameFor(BundleSpec spec) =>
      '${spec.mainBinaryName}-${spec.version.semantic}-$architecture.AppImage';

  Future<String> bundle(BundleSpec spec) async {
    final Directory app = Directory(spec.appDirectory);
    if (!app.existsSync()) {
      throw BundleFailure(
        'the built application is not at ${spec.appDirectory}.',
        remedy: 'Run flutter build linux --release first.',
      );
    }

    final String runtime = _runtimeFor();
    final Directory output = Directory(spec.outputDirectory)
      ..createSync(recursive: true);
    final Directory stage = Directory(p.join(output.path, 'appimage'));
    if (stage.existsSync()) {
      stage.deleteSync(recursive: true);
    }
    final Directory root = Directory(p.join(stage.path, 'AppDir'))
      ..createSync(recursive: true);

    _copyPayload(app, Directory(p.join(root.path, AppRun.payloadDirectory)));
    _writeLauncher(root, spec);
    _writeIcons(root, spec);

    final String image = p.join(stage.path, 'payload.squashfs');
    final ProcessOutcome squashed = await runner.run(mksquashfs, <String>[
      root.absolute.path,
      image,
      '-root-owned',
      '-noappend',
      '-quiet',
      '-no-progress',
    ]);
    if (!squashed.succeeded) {
      throw BundleFailure(
        '$mksquashfs exited with ${squashed.exitCode} instead of writing the '
        'filesystem the AppImage carries.',
        remedy: squashed.firstDiagnostic,
      );
    }

    final String destination = p.join(output.path, fileNameFor(spec));
    AppendedImage.write(
      runtime: runtime,
      image: image,
      destination: destination,
    );
    _chmod(destination, AppRun.mode);
    stage.deleteSync(recursive: true);
    return destination;
  }

  String _runtimeFor() {
    final String? given = runtimePath;
    if (given == null || given.trim().isEmpty) {
      throw BundleFailure(
        'no AppImage runtime was given, and one cannot be invented.',
        remedy:
            'An AppImage is that runtime with a squashfs appended to it. It '
            'is a few hundred kilobytes of someone else\'s ELF, so this '
            'toolkit does not carry a copy: take runtime-$architecture from '
            '$_runtimeSource and pass its path.',
      );
    }

    final TargetArch built = ElfHeader.read(given).arch;
    if (built != arch) {
      throw BundleFailure(
        'the runtime at $given is ${built.appImage} and the app is '
        '$architecture.',
        remedy:
            'The runtime is what the kernel executes, so a mismatch produces '
            'a file that reports "cannot execute binary file" and says '
            'nothing about which half is wrong.',
      );
    }
    return given;
  }

  void _copyPayload(Directory app, Directory into) {
    into.createSync(recursive: true);
    for (final FileSystemEntity entity in app.listSync(
      recursive: true,
      followLinks: false,
    )) {
      final String relative = p.relative(entity.path, from: app.path);
      final String landing = p.join(into.path, relative);

      if (entity is Link) {
        Directory(p.dirname(landing)).createSync(recursive: true);
        Link(landing).createSync(entity.targetSync());
        continue;
      }
      if (entity is! File) {
        continue;
      }
      Directory(p.dirname(landing)).createSync(recursive: true);
      entity.copySync(landing);
      _chmod(landing, entity.statSync().mode & 0x1FF);
    }
  }

  void _writeLauncher(Directory root, BundleSpec spec) {
    final String launcher = p.join(root.path, AppRun.fileName);
    File(launcher).writeAsStringSync(AppRun.forBinary(spec.mainBinaryName));
    _chmod(launcher, AppRun.mode);

    final DesktopEntry entry = DesktopEntry.insideBundle(spec);
    File(p.join(root.path, entry.fileName)).writeAsStringSync(entry.render());
    final File installed = File(
      p.join(root.path, 'usr', 'share', 'applications', entry.fileName),
    )..parent.createSync(recursive: true);
    installed.writeAsStringSync(entry.render());
  }

  void _writeIcons(Directory root, BundleSpec spec) {
    final IconSource? source = icon;
    if (source == null) {
      return;
    }

    final List<HicolorIcon> themed = HicolorIcons.fromSource(
      source: source,
      appId: spec.identifier,
    );
    for (final HicolorIcon each in themed) {
      File(p.join(root.path, each.installedPath.substring(1)))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(each.png);
    }
    File(
      p.join(root.path, '${spec.identifier}.png'),
    ).writeAsBytesSync(themed.last.png);
  }

  void _chmod(String path, int mode) {
    Process.runSync('chmod', <String>[
      mode.toRadixString(8).padLeft(3, '0'),
      path,
    ]);
  }
}
