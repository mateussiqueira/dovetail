import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/spec/bundle_spec.dart';
import 'package:path/path.dart' as p;
import 'package:dovetail_process_runner/dovetail_process_runner.dart';

final class ShlibDeps {
  const ShlibDeps({
    required this.runner,
    this.executable = 'dpkg-shlibdeps',
    this.scratchDirectory,
    this.baseDirectory,
  });

  final ProcessRunner runner;
  final String executable;
  final String? scratchDirectory;

  /// What a relative [BundleSpec.appDirectory] is relative TO.
  ///
  /// Without it the answer is the process working directory, which a library
  /// has no business reading: it is shared by every isolate in a test run, so
  /// a suite that moves it changes what this resolves to, and the failure
  /// shows up somewhere else entirely.
  final String? baseDirectory;

  static const String _field = 'shlibs:Depends=';
  static const String _control =
      'Source: dovetail\n\n'
      'Package: dovetail\n'
      'Architecture: any\n';

  Future<List<String>> forBundle(BundleSpec spec) async {
    final List<String> objects = _objectsOf(spec);
    if (objects.isEmpty) {
      return const <String>[];
    }

    final String? given = scratchDirectory;
    final Directory scratch = given == null
        ? Directory.systemTemp.createTempSync('dovetail_shlibs')
        : (Directory(given)..createSync(recursive: true));
    File(p.join(scratch.path, 'debian', 'control'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_control);

    try {
      final ProcessOutcome read = await runner.run(executable, <String>[
        '-O',
        '--ignore-missing-info',
        ...objects,
      ], workingDirectory: scratch.path);
      if (!read.succeeded) {
        throw BundleFailure(
          '$executable exited with ${read.exitCode} instead of naming the '
          'packages this build needs.',
          remedy:
              'A Debian package with no Depends installs and then fails to '
              'start, so this is not something to skip quietly. Pass '
              '--no-derive-deb-depends to build without it. '
              '${read.firstDiagnostic}',
        );
      }
      return parse(read.stdout);
    } on ProcessException {
      return const <String>[];
    } finally {
      scratch.deleteSync(recursive: true);
    }
  }

  static List<String> parse(String printed) {
    for (final String line in printed.split('\n')) {
      if (!line.startsWith(_field)) {
        continue;
      }
      return line
          .substring(_field.length)
          .split(',')
          .map((String entry) => entry.trim())
          .where((String entry) => entry.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  List<String> _objectsOf(BundleSpec spec) {
    final String? base = baseDirectory;
    final Directory app = Directory(
      base == null || p.isAbsolute(spec.appDirectory)
          ? spec.appDirectory
          : p.join(base, spec.appDirectory),
    ).absolute;
    if (!app.existsSync()) {
      return const <String>[];
    }

    final String binary = p.join(app.path, spec.mainBinaryName);
    final List<String> shared =
        app
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((File file) => file.absolute.path)
            .where((String path) => path.endsWith('.so'))
            .toList()
          ..sort();

    return <String>[if (File(binary).existsSync()) binary, ...shared];
  }
}
