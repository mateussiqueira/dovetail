import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_icon'));
  tearDown(() => root.deleteSync(recursive: true));

  String writePng({required int width, required int height}) {
    final img.Image image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgba8(20, 80, 160, 255));
    final String path = p.join(root.path, '${width}x$height.png');
    File(path).writeAsBytesSync(img.encodePng(image));
    return path;
  }

  IconSource square512() => IconSource.read(writePng(width: 512, height: 512));

  group('IconSource', () {
    test('should read the header, not the file name', () {
      final String misnamed = p.join(root.path, '128x128.png');
      File(misnamed).writeAsBytesSync(
        File(writePng(width: 512, height: 512)).readAsBytesSync(),
      );

      expect(
        IconSource.read(misnamed).size,
        512,
        reason:
            'the icon this replaced was named 128x128.png and was 512 square, '
            'which is what a design tool exports and what a reader trusting '
            'the name would get wrong',
      );
    });

    test('should skip the chunks a design tool leaves before the image', () {
      final Uint8List plain = File(
        writePng(width: 512, height: 512),
      ).readAsBytesSync();
      final String decorated = p.join(root.path, 'decorated.png');
      File(decorated).writeAsBytesSync(_withAncillaryChunks(plain));

      expect(
        IconSource.read(decorated).size,
        512,
        reason:
            'a PNG out of a design tool carries pHYs, tEXt and often an ICC '
            'profile between IHDR and IDAT, and a reader that assumes IDAT '
            'comes next reads the wrong bytes as a size',
      );
    });

    test('should refuse a file that is not a PNG', () {
      final String path = p.join(root.path, 'notes.png');
      File(path).writeAsStringSync('not an image');
      expect(() => IconSource.read(path), throwsA(isA<BundleFailure>()));
    });

    test('should refuse a path that does not exist', () {
      expect(
        () => IconSource.read(p.join(root.path, 'absent.png')),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should refuse a non-square icon rather than stretch it', () {
      expect(
        () => IconSource.read(writePng(width: 512, height: 256)),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('stretch'),
          ),
        ),
      );
    });

    test('should refuse a source too small for a macOS bundle', () {
      expect(
        () => IconSource.read(writePng(width: 256, height: 256)),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should shrink and never upscale', () {
      final IconSource source = square512();
      expect(img.decodePng(source.pngAt(64))!.width, 64);
      expect(() => source.pngAt(1024), throwsA(isA<BundleFailure>()));
    });

    test('every derived size should be a decodable square png', () {
      final IconSource source = square512();
      for (final int edge in <int>[16, 32, 128, 512]) {
        final img.Image? decoded = img.decodePng(source.pngAt(edge));
        expect(decoded, isNotNull, reason: '$edge');
        expect(decoded!.width, edge);
        expect(decoded.height, edge);
      }
    });
  });

  group('IcoWriter', () {
    test('should write the header layout Windows reads', () {
      final Uint8List ico = IcoWriter.fromSource(
        square512(),
        sizes: const <int>[16, 32, 256],
      );
      final ByteData view = ByteData.sublistView(ico);
      expect(view.getUint16(0, Endian.little), 0, reason: 'reserved');
      expect(view.getUint16(2, Endian.little), 1, reason: 'type icon');
      expect(view.getUint16(4, Endian.little), 3, reason: 'count');
    });

    test('a 256px entry should record its edge as zero', () {
      final Uint8List ico = IcoWriter.fromSource(
        square512(),
        sizes: const <int>[256],
      );
      expect(ico[6], 0);
      expect(ico[7], 0);
    });

    test('every entry should point at a payload that starts with PNG', () {
      final Uint8List ico = IcoWriter.fromSource(
        square512(),
        sizes: const <int>[16, 48, 256],
      );
      final ByteData view = ByteData.sublistView(ico);
      final int count = view.getUint16(4, Endian.little);
      for (int index = 0; index < count; index++) {
        final int entry = 6 + index * 16;
        final int offset = view.getUint32(entry + 12, Endian.little);
        final int length = view.getUint32(entry + 8, Endian.little);
        expect(offset + length, lessThanOrEqualTo(ico.length));
        expect(ico.sublist(offset, offset + 8), <int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ], reason: 'entry $index');
      }
    });

    test('should refuse an entry larger than an ico can express', () {
      expect(
        () => IcoWriter.encode(<int, Uint8List>{
          512: Uint8List.fromList(<int>[0]),
        }),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should refuse an ico with no entry', () {
      expect(
        () => IcoWriter.encode(const <int, Uint8List>{}),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('the same source should produce the same bytes', () {
      final IconSource source = square512();
      expect(IcoWriter.fromSource(source), IcoWriter.fromSource(source));
    });

    test('the system file command should read it as a Windows icon', () {
      if (!_which('file')) {
        markTestSkipped('the file(1) tool is not installed on this host');
        return;
      }
      final String path = p.join(root.path, 'icon.ico');
      File(path).writeAsBytesSync(IcoWriter.fromSource(square512()));

      final ProcessResult read = Process.runSync('file', <String>['-b', path]);
      expect(read.stdout.toString(), contains('MS Windows icon resource'));
      expect(read.stdout.toString(), contains('7 icons'));
    });

    test('sips should open it and report the largest entry', () {
      if (!Platform.isMacOS) {
        markTestSkipped('sips is a macOS tool');
        return;
      }
      final String path = p.join(root.path, 'icon.ico');
      File(path).writeAsBytesSync(IcoWriter.fromSource(square512()));

      final String read = Process.runSync('sips', <String>[
        '-g',
        'format',
        '-g',
        'pixelWidth',
        path,
      ]).stdout.toString();
      expect(read, contains('format: ico'));
      expect(read, contains('pixelWidth: 256'));
    });
  });

  group('IcnsWriter', () {
    test('should start with the icns magic and its own total length', () {
      final Uint8List icns = IcnsWriter.fromSource(square512());
      expect(String.fromCharCodes(icns.sublist(0, 4)), 'icns');
      expect(
        ByteData.sublistView(icns).getUint32(4),
        icns.length,
        reason: 'the header length covers the whole file, header included',
      );
    });

    test('every chunk length should cover its own header', () {
      final Uint8List icns = IcnsWriter.fromSource(square512());
      final ByteData view = ByteData.sublistView(icns);
      int cursor = 8;
      int chunks = 0;
      while (cursor < icns.length) {
        final int length = view.getUint32(cursor + 4);
        expect(length, greaterThan(8));
        expect(cursor + length, lessThanOrEqualTo(icns.length));
        expect(icns.sublist(cursor + 8, cursor + 16), <int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]);
        cursor += length;
        chunks++;
      }
      expect(cursor, icns.length);
      expect(chunks, IcnsWriter.appleEntries.length);
    });

    test('should refuse a type that is not four characters', () {
      expect(
        () => IcnsWriter.encode(<String, Uint8List>{
          'ic8': Uint8List.fromList(<int>[0]),
        }),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('shifts every chunk'),
          ),
        ),
      );
    });

    test('should refuse an icns with no entry', () {
      expect(
        () => IcnsWriter.encode(const <String, Uint8List>{}),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('iconutil should disassemble what this wrote', () {
      if (!Platform.isMacOS) {
        markTestSkipped('iconutil is a macOS tool');
        return;
      }
      final String path = p.join(root.path, 'icon.icns');
      File(path).writeAsBytesSync(IcnsWriter.fromSource(square512()));

      final String iconset = p.join(root.path, 'back.iconset');
      final ProcessResult converted = Process.runSync('iconutil', <String>[
        '-c',
        'iconset',
        '-o',
        iconset,
        path,
      ]);
      expect(
        converted.exitCode,
        0,
        reason:
            'iconutil is Apple deciding whether this container is real: '
            '${converted.stderr}',
      );

      final Set<String> produced = Directory(iconset)
          .listSync()
          .map((FileSystemEntity entity) => p.basename(entity.path))
          .toSet();
      expect(
        produced,
        containsAll(<String>[
          'icon_16x16.png',
          'icon_16x16@2x.png',
          'icon_32x32.png',
          'icon_32x32@2x.png',
          'icon_128x128.png',
          'icon_128x128@2x.png',
          'icon_256x256.png',
          'icon_256x256@2x.png',
          'icon_512x512.png',
        ]),
        reason: 'each name is iconutil agreeing on what a type code means',
      );
    });

    test('sips should read it as an icns at the largest size', () {
      if (!Platform.isMacOS) {
        markTestSkipped('sips is a macOS tool');
        return;
      }
      final String path = p.join(root.path, 'icon.icns');
      File(path).writeAsBytesSync(IcnsWriter.fromSource(square512()));

      final String read = Process.runSync('sips', <String>[
        '-g',
        'format',
        '-g',
        'pixelWidth',
        path,
      ]).stdout.toString();
      expect(read, contains('format: icns'));
      expect(read, contains('pixelWidth: 512'));
    });
  });

  group('HicolorIcons', () {
    test('should install under the theme path a launcher searches', () {
      final List<HicolorIcon> icons = HicolorIcons.fromSource(
        source: square512(),
        appId: 'io.example.client',
      );
      expect(
        icons.map((HicolorIcon icon) => icon.installedPath),
        contains('/usr/share/icons/hicolor/48x48/apps/io.example.client.png'),
      );
      expect(icons, hasLength(HicolorIcons.freedesktopSizes.length));
    });

    test('the file name should be the app id the desktop entry points at', () {
      final BundleSpec spec = BundleSpec(
        productName: 'Example',
        manufacturer: 'Example Ltda',
        identifier: 'io.example.client',
        version: AppVersion.parse('1.0.0'),
        mainBinaryName: 'client',
        appDirectory: root.path,
        outputDirectory: root.path,
      );
      final String iconName = DesktopEntry.forSpec(spec)
          .render()
          .split('\n')
          .firstWhere((String line) => line.startsWith('Icon='))
          .substring(5);

      expect(
        HicolorIcons.fromSource(
          source: square512(),
          appId: spec.identifier,
        ).first.installedPath,
        endsWith('/$iconName.png'),
        reason:
            'the entry says Icon=<name> and the launcher looks for <name>.png '
            'in the theme; a mismatch shows no icon at all',
      );
    });
  });

  group('the deb it produces', () {
    test('should carry an icon for every themed size', () async {
      final String app = p.join(root.path, 'bundle');
      Directory(app).createSync();
      File(p.join(app, 'client')).writeAsStringSync('binary');

      final String deb = await DebBundler(icon: square512()).bundle(
        BundleSpec(
          productName: 'Example',
          manufacturer: 'Example Ltda',
          identifier: 'io.example.client',
          version: AppVersion.parse('1.0.0'),
          mainBinaryName: 'client',
          appDirectory: app,
          outputDirectory: p.join(root.path, 'out'),
        ),
      );

      final ProcessResult extracted = Process.runSync('ar', <String>[
        'p',
        deb,
        'data.tar.gz',
      ], stdoutEncoding: null);
      final Archive data = TarDecoder().decodeBytes(
        const GZipDecoder().decodeBytes(extracted.stdout as List<int>),
      );

      final Iterable<String> icons = data.files
          .where((ArchiveFile file) => file.isFile)
          .map((ArchiveFile file) => file.name)
          .where((String name) => name.startsWith('usr/share/icons/hicolor'));
      expect(icons, hasLength(HicolorIcons.freedesktopSizes.length));
      expect(
        icons,
        contains('usr/share/icons/hicolor/256x256/apps/io.example.client.png'),
      );
    });
  });
}

Uint8List _chunk(String type, List<int> payload) {
  final BytesBuilder body = BytesBuilder()
    ..add(type.codeUnits)
    ..add(payload);
  final Uint8List bytes = body.toBytes();
  final BytesBuilder out = BytesBuilder()
    ..add(<int>[
      (payload.length >> 24) & 0xFF,
      (payload.length >> 16) & 0xFF,
      (payload.length >> 8) & 0xFF,
      payload.length & 0xFF,
    ])
    ..add(bytes)
    ..add(_crcOf(bytes));
  return out.toBytes();
}

Uint8List _crcOf(Uint8List bytes) {
  int crc = 0xFFFFFFFF;
  for (final int byte in bytes) {
    crc ^= byte;
    for (int bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  crc ^= 0xFFFFFFFF;
  return Uint8List.fromList(<int>[
    (crc >> 24) & 0xFF,
    (crc >> 16) & 0xFF,
    (crc >> 8) & 0xFF,
    crc & 0xFF,
  ]);
}

Uint8List _withAncillaryChunks(Uint8List png) {
  const int afterIhdr = 8 + 4 + 4 + 13 + 4;
  return Uint8List.fromList(<int>[
    ...png.sublist(0, afterIhdr),
    ..._chunk('pHYs', <int>[0, 0, 0x0B, 0x13, 0, 0, 0x0B, 0x13, 1]),
    ..._chunk('tEXt', 'Software\u0000Dovetail'.codeUnits),
    ...png.sublist(afterIhdr),
  ]);
}

bool _which(String tool) {
  try {
    return Process.runSync('which', <String>[tool]).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
