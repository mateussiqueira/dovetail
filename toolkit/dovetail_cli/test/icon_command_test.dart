import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String source;
  late CommandRunner<int> runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_iconcmd');
    final img.Image image = img.Image(width: 512, height: 512);
    img.fill(image, color: img.ColorRgba8(10, 60, 120, 255));
    source = p.join(root.path, 'source.png');
    File(source).writeAsBytesSync(img.encodePng(image));
    runner = CommandRunner<int>('dovetail', 'test')..addCommand(IconCommand());
  });

  tearDown(() => root.deleteSync(recursive: true));

  String out() => p.join(root.path, 'icons');

  test('should write every format by default', () async {
    final int code =
        await runner.run(<String>[
          'icon',
          '--source',
          source,
          '--out',
          out(),
          '--app-id',
          'io.example.client',
        ]) ??
        1;

    expect(code, 0);
    expect(File(p.join(out(), 'icon.ico')).existsSync(), true);
    expect(File(p.join(out(), 'icon.icns')).existsSync(), true);
    expect(
      Directory(
        p.join(out(), 'hicolor'),
      ).listSync(recursive: true).whereType<File>(),
      hasLength(8),
    );
  });

  test('should write only the formats it was asked for', () async {
    await runner.run(<String>[
      'icon',
      '--source',
      source,
      '--out',
      out(),
      '--format',
      'ico',
    ]);

    expect(File(p.join(out(), 'icon.ico')).existsSync(), true);
    expect(File(p.join(out(), 'icon.icns')).existsSync(), false);
    expect(Directory(p.join(out(), 'hicolor')).existsSync(), false);
  });

  test('hicolor without an app id should be refused', () async {
    await expectLater(
      runner.run(<String>[
        'icon',
        '--source',
        source,
        '--out',
        out(),
        '--format',
        'hicolor',
      ]),
      throwsA(
        isA<UsageException>().having(
          (UsageException error) => error.usage,
          'usage',
          contains('a name nothing reads'),
        ),
      ),
    );
  });

  test('a source that is too small should be refused', () async {
    final img.Image small = img.Image(width: 128, height: 128);
    final String path = p.join(root.path, 'small.png');
    File(path).writeAsBytesSync(img.encodePng(small));

    await expectLater(
      runner.run(<String>[
        'icon',
        '--source',
        path,
        '--out',
        out(),
        '--format',
        'ico',
      ]),
      throwsA(
        isA<BundleFailure>().having(
          (BundleFailure failure) => failure.message,
          'message',
          contains('below the 512'),
        ),
      ),
    );
  });

  test('the themed files should be named after the app id', () async {
    await runner.run(<String>[
      'icon',
      '--source',
      source,
      '--out',
      out(),
      '--app-id',
      'io.example.client',
      '--format',
      'hicolor',
    ]);

    final Iterable<String> names = Directory(p.join(out(), 'hicolor'))
        .listSync(recursive: true)
        .whereType<File>()
        .map((File file) => p.basename(file.path));

    expect(names.toSet(), <String>{'io.example.client.png'});
  });
}
