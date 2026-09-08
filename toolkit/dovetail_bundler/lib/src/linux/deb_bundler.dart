import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/icon/hicolor_icons.dart';
import 'package:dovetail_bundler/src/icon/icon_source.dart';
import 'package:dovetail_bundler/src/linux/desktop_entry.dart';
import 'package:dovetail_bundler/src/linux/polkit_policy.dart';
import 'package:dovetail_bundler/src/linux/service_scripts.dart';
import 'package:dovetail_bundler/src/linux/systemd_unit.dart';
import 'package:dovetail_bundler/src/spec/bundle_spec.dart';
import 'package:dovetail_bundler/src/spec/staged_file.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:path/path.dart' as p;

const String _debianBinary = '2.0\n';
const int _directoryMode = 0x1ED;

final class DebBundler {
  const DebBundler({
    this.arch = TargetArch.x86_64,
    this.depends = const <String>[],
    this.unit,
    this.policy,
    this.scripts,
    this.icon,
  });

  final TargetArch arch;
  final List<String> depends;
  final SystemdUnit? unit;
  final PolkitPolicy? policy;
  final ServiceScripts? scripts;
  final IconSource? icon;

  String get architecture => arch.debian;

  void _refuseHalfConfiguredService() {
    if (unit == null && scripts == null) {
      return;
    }
    if (unit == null || scripts == null) {
      throw const BundleFailure(
        'a unit without maintainer scripts, or scripts without a unit.',
        remedy:
            'A unit that nothing enables never starts, and scripts that '
            'enable a unit the package did not install fail on every '
            'install. Give both or neither.',
      );
    }
    if (scripts!.unitFileName != unit!.fileName) {
      throw BundleFailure(
        'the scripts enable "${scripts!.unitFileName}" but the package '
        'installs "${unit!.fileName}".',
        remedy: 'They have to name the same file.',
      );
    }
  }

  String fileNameFor(BundleSpec spec) =>
      '${spec.mainBinaryName}_${spec.version.semantic}_$architecture.deb';

  String controlFor(BundleSpec spec, {required int installedKiB}) {
    final StringBuffer control = StringBuffer()
      ..writeln('Package: ${spec.mainBinaryName}')
      ..writeln('Version: ${spec.version.semantic}')
      ..writeln('Architecture: $architecture')
      ..writeln('Installed-Size: $installedKiB')
      ..writeln('Maintainer: ${spec.manufacturer}')
      ..writeln('Section: net')
      ..writeln('Priority: optional');

    if (spec.homepage != null) {
      control.writeln('Homepage: ${spec.homepage}');
    }
    if (depends.isNotEmpty) {
      control.writeln('Depends: ${depends.join(', ')}');
    }
    control.writeln('Description: ${spec.productName}');

    return control.toString();
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
    Directory(spec.outputDirectory).createSync(recursive: true);

    final Archive data = Archive();
    int totalBytes = 0;
    for (final FileSystemEntity entity in app.listSync(
      recursive: true,
      followLinks: false,
    )) {
      final String installed =
          'usr/lib/${spec.mainBinaryName}/'
          '${installedName(entity.path, from: app.path)}';

      if (entity is Link) {
        data.addFile(ArchiveFile.symlink(installed, entity.targetSync()));
        continue;
      }
      if (entity is! File) {
        continue;
      }

      final Uint8List bytes = entity.readAsBytesSync();
      totalBytes += bytes.length;
      data.addFile(
        ArchiveFile(installed, bytes.length, bytes)
          ..mode = entity.statSync().mode & 0x1FF,
      );
    }

    if (data.isEmpty) {
      throw BundleFailure('${spec.appDirectory} has no files to package.');
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
      final Uint8List bytes = source.readAsBytesSync();
      data.addFile(
        ArchiveFile(
          staged.destination.replaceFirst(RegExp('^/+'), ''),
          bytes.length,
          bytes,
        )..mode = source.statSync().mode & 0x1FF,
      );
    }

    data.addFile(_desktopEntry(spec));
    if (icon != null) {
      for (final HicolorIcon themed in HicolorIcons.fromSource(
        source: icon!,
        appId: spec.identifier,
      )) {
        data.addFile(
          ArchiveFile(
            themed.installedPath.substring(1),
            themed.png.length,
            themed.png,
          ),
        );
      }
    }
    if (unit != null) {
      data.addFile(
        _textFile('usr/lib/systemd/system/${unit!.fileName}', unit!.render()),
      );
    }
    if (policy != null) {
      data.addFile(
        _textFile(
          'usr/share/polkit-1/actions/${policy!.fileName}',
          policy!.render(),
        ),
      );
    }

    final Uint8List dataTarGz = _tarGz(_withDirectories(data));

    final Archive control = Archive()
      ..addFile(
        _textFile(
          'control',
          controlFor(spec, installedKiB: (totalBytes / 1024).ceil()),
        ),
      );
    if (scripts != null) {
      control
        ..addFile(_executableFile('postinst', scripts!.debianPostinst))
        ..addFile(_executableFile('prerm', scripts!.debianPrerm))
        ..addFile(_executableFile('postrm', scripts!.debianPostrm));
    }
    final Uint8List controlTarGz = _tarGz(control);

    final String destination = p.join(spec.outputDirectory, fileNameFor(spec));
    File(destination).writeAsBytesSync(
      writeAr(<ArMember>[
        ArMember(
          'debian-binary',
          Uint8List.fromList(utf8.encode(_debianBinary)),
        ),
        ArMember('control.tar.gz', controlTarGz),
        ArMember('data.tar.gz', dataTarGz),
      ]),
    );

    return destination;
  }

  Archive _withDirectories(Archive data) {
    final Archive payload = Archive();
    for (final String directory in directoriesFor(
      data.map((ArchiveFile member) => member.name),
    )) {
      payload.addFile(ArchiveFile.directory(directory)..mode = _directoryMode);
    }
    for (final ArchiveFile member in data) {
      payload.addFile(member);
    }
    return payload;
  }

  static String installedName(String path, {required String from}) =>
      p.posix.joinAll(p.split(p.relative(path, from: from)));

  static List<String> directoriesFor(Iterable<String> members) {
    final SplayTreeSet<String> directories = SplayTreeSet<String>();
    for (final String member in members) {
      String walked = '';
      for (final String segment in p.posix.split(p.posix.dirname(member))) {
        if (segment.isEmpty || segment == '.') {
          continue;
        }
        walked = walked.isEmpty ? segment : '$walked/$segment';
        directories.add('$walked/');
      }
    }
    return directories.toList();
  }

  ArchiveFile _desktopEntry(BundleSpec spec) {
    final DesktopEntry entry = DesktopEntry.forSpec(spec);
    return _textFile(
      'usr/share/applications/${entry.fileName}',
      entry.render(),
    );
  }

  ArchiveFile _textFile(String name, String content) {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(content));
    return ArchiveFile(name, bytes.length, bytes);
  }

  ArchiveFile _executableFile(String name, String content) =>
      _textFile(name, content)..mode = ServiceScripts.scriptMode;

  Uint8List _tarGz(Archive archive) {
    final List<int> tar = TarEncoder().encode(archive);
    if (tar.isEmpty) {
      throw const BundleFailure('the tar encoder produced nothing.');
    }
    return Uint8List.fromList(const GZipEncoder().encode(tar));
  }

  static Uint8List writeAr(List<ArMember> members) {
    final BytesBuilder out = BytesBuilder()..add(utf8.encode('!<arch>\n'));

    for (final ArMember member in members) {
      out.add(utf8.encode(_pad(member.name, 16)));
      out.add(utf8.encode(_pad('0', 12)));
      out.add(utf8.encode(_pad('0', 6)));
      out.add(utf8.encode(_pad('0', 6)));
      out.add(utf8.encode(_pad('100644', 8)));
      out.add(utf8.encode(_pad('${member.bytes.length}', 10)));
      out.add(utf8.encode('`\n'));
      out.add(member.bytes);
      if (member.bytes.length.isOdd) {
        out.add(utf8.encode('\n'));
      }
    }

    return out.toBytes();
  }

  static String _pad(String value, int width) =>
      value.length >= width ? value.substring(0, width) : value.padRight(width);
}

final class ArMember {
  const ArMember(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}
