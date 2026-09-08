import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';

final class ElfHeader {
  const ElfHeader._(this.arch);

  factory ElfHeader.read(String path) {
    final File file = File(path);
    if (!file.existsSync()) {
      throw BundleFailure('there is no file at $path to read as an ELF.');
    }

    final RandomAccessFile handle = file.openSync();
    try {
      final Uint8List head = handle.readSync(_headerBytes);
      return ElfHeader._(_archOf(head, path));
    } finally {
      handle.closeSync();
    }
  }

  final TargetArch arch;

  static const int _headerBytes = 20;
  static const int _machineOffset = 18;
  static const int _x86_64 = 0x3E;
  static const int _aarch64 = 0xB7;
  static const List<int> _magic = <int>[0x7F, 0x45, 0x4C, 0x46];

  static TargetArch _archOf(Uint8List head, String path) {
    if (head.length < _headerBytes) {
      throw BundleFailure('$path is too short to be an ELF binary.');
    }
    for (int index = 0; index < _magic.length; index++) {
      if (head[index] != _magic[index]) {
        throw BundleFailure(
          '$path does not start with the ELF magic number.',
          remedy:
              'An AppImage runtime is a Linux ELF binary. A page of HTML '
              'saved by a browser that followed a redirect looks like this.',
        );
      }
    }

    final int machine = head[_machineOffset] | (head[_machineOffset + 1] << 8);
    return switch (machine) {
      _x86_64 => TargetArch.x86_64,
      _aarch64 => TargetArch.arm64,
      _ => throw BundleFailure(
        '$path is built for ELF machine 0x${machine.toRadixString(16)}.',
        remedy:
            'This bundler builds x86_64 and arm64. The runtime has to match '
            'the architecture the app was compiled for, and nothing at run '
            'time will tell the user why it does not start.',
      ),
    };
  }
}
