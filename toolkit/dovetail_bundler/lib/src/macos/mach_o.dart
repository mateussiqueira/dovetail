import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_bundler/src/spec/target_arch.dart';

enum MachOKind { thin, fat, notMachO }

final class MachOInfo {
  const MachOInfo({
    required this.kind,
    required this.architectures,
    this.unknownCpuTypes = const <int>{},
  });

  static const MachOInfo none = MachOInfo(
    kind: MachOKind.notMachO,
    architectures: <TargetArch>{},
  );

  final MachOKind kind;
  final Set<TargetArch> architectures;
  final Set<int> unknownCpuTypes;

  bool get isMachO => kind != MachOKind.notMachO;

  bool get isUniversal => architectures.length > 1;

  @override
  String toString() =>
      'MachOInfo(${kind.name}, '
      '${architectures.map((TargetArch a) => a.apple).join('+')})';
}

abstract final class MachO {
  static const int _thin64LittleEndian = 0xCFFAEDFE;
  static const int _thin64BigEndian = 0xFEEDFACF;
  static const int _thin32LittleEndian = 0xCEFAEDFE;
  static const int _thin32BigEndian = 0xFEEDFACE;
  static const int _fat32 = 0xCAFEBABE;
  static const int _fat64 = 0xCAFEBABF;

  static const int cpuTypeX86_64 = 0x01000007;
  static const int cpuTypeArm64 = 0x0100000C;

  static const int _headerBytes = 4096;

  static MachOInfo read(String path) {
    final File file = File(path);
    if (!file.existsSync()) {
      return MachOInfo.none;
    }

    final RandomAccessFile handle = file.openSync();
    try {
      final int length = handle.lengthSync();
      if (length < 8) {
        return MachOInfo.none;
      }
      final Uint8List head = handle.readSync(
        length < _headerBytes ? length : _headerBytes,
      );
      return parse(head);
    } finally {
      handle.closeSync();
    }
  }

  static MachOInfo parse(Uint8List head) {
    if (head.length < 8) {
      return MachOInfo.none;
    }
    final ByteData view = ByteData.sublistView(head);
    final int magic = view.getUint32(0);

    return switch (magic) {
      _fat32 || _fat64 => _fat(view, wide: magic == _fat64),
      _thin64LittleEndian ||
      _thin32LittleEndian => _thin(view, littleEndian: true),
      _thin64BigEndian || _thin32BigEndian => _thin(view, littleEndian: false),
      _ => MachOInfo.none,
    };
  }

  static MachOInfo _thin(ByteData view, {required bool littleEndian}) {
    final int cpuType = view.getUint32(
      4,
      littleEndian ? Endian.little : Endian.big,
    );
    final TargetArch? arch = archFor(cpuType);
    return MachOInfo(
      kind: MachOKind.thin,
      architectures: arch == null ? const <TargetArch>{} : <TargetArch>{arch},
      unknownCpuTypes: arch == null ? <int>{cpuType} : const <int>{},
    );
  }

  static MachOInfo _fat(ByteData view, {required bool wide}) {
    final int count = view.getUint32(4);
    final int entryBytes = wide ? 32 : 20;
    final Set<TargetArch> found = <TargetArch>{};
    final Set<int> unknown = <int>{};

    for (int index = 0; index < count; index++) {
      final int offset = 8 + index * entryBytes;
      if (offset + 4 > view.lengthInBytes) {
        break;
      }
      final int cpuType = view.getUint32(offset);
      final TargetArch? arch = archFor(cpuType);
      if (arch == null) {
        unknown.add(cpuType);
      } else {
        found.add(arch);
      }
    }

    return MachOInfo(
      kind: MachOKind.fat,
      architectures: found,
      unknownCpuTypes: unknown,
    );
  }

  static TargetArch? archFor(int cpuType) => switch (cpuType) {
    cpuTypeX86_64 => TargetArch.x86_64,
    cpuTypeArm64 => TargetArch.arm64,
    _ => null,
  };
}
