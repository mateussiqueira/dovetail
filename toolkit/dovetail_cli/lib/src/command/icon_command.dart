import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:dovetail_cli/src/command/required_option.dart';

final class IconCommand extends Command<int> {
  IconCommand() {
    argParser
      ..addOption(
        'source',
        help: 'one square PNG, 512px or larger; everything else is derived',
      )
      ..addOption(
        'out',
        help: 'directory for the generated .ico, .icns and theme PNGs',
      )
      ..addOption(
        'app-id',
        help: 'reverse-domain id the Linux theme icons are named after',
      )
      ..addMultiOption(
        'format',
        allowed: <String>['ico', 'icns', 'hicolor'],
        defaultsTo: <String>['ico', 'icns', 'hicolor'],
      );
  }

  @override
  String get name => 'icon';

  @override
  String get description =>
      'Derives every platform icon from one PNG. Never upscales.';

  @override
  Future<int> run() async {
    final ArgResults args = argResults!;
    final List<String> formats = args.multiOption('format');
    final String? appId = args.option('app-id');

    if (formats.contains('hicolor') && appId == null) {
      throw UsageException(
        'the hicolor icons need --app-id.',
        'A launcher looks for <app id>.png in the theme, because that is the '
            'name the .desktop entry points at. Without it the files would be '
            'installed under a name nothing reads.\n\n$usage',
      );
    }

    final IconSource source = IconSource.read(
      requiredOption(args, 'source', usage),
    );
    final String out = requiredOption(args, 'out', usage);
    Directory(out).createSync(recursive: true);

    stdout.writeln('source  ${source.size}px square');

    if (formats.contains('ico')) {
      final String path = p.join(out, 'icon.ico');
      File(path).writeAsBytesSync(IcoWriter.fromSource(source));
      stdout.writeln('ico     $path  (${IcoWriter.windowsSizes.length} sizes)');
    }

    if (formats.contains('icns')) {
      final String path = p.join(out, 'icon.icns');
      File(path).writeAsBytesSync(IcnsWriter.fromSource(source));
      stdout.writeln(
        'icns    $path  (${IcnsWriter.appleEntries.length} entries)',
      );
    }

    if (formats.contains('hicolor')) {
      int written = 0;
      for (final HicolorIcon icon in HicolorIcons.fromSource(
        source: source,
        appId: appId!,
      )) {
        final File file = File(
          p.join(out, 'hicolor', icon.installedPath.replaceFirst('/', '')),
        )..parent.createSync(recursive: true);
        file.writeAsBytesSync(icon.png);
        written++;
      }
      stdout.writeln('hicolor ${p.join(out, 'hicolor')}  ($written sizes)');
    }

    return 0;
  }
}
