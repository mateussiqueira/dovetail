import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the repository is, for a test that needs a real artefact from it.
///
/// It reads DOVETAIL_REPO_ROOT first, because `Directory.current` belongs to
/// the PROCESS and `dart test` runs every suite as an isolate of one process:
/// a suite that moves it changes what every other suite resolves, and the
/// damage lands somewhere else. Walking up from the cwd stays as a courtesy
/// for `dart test` typed by hand in a package directory.
///
/// It THROWS when it cannot find the root, and that is the whole point. The
/// copies this replaced returned null, so `_inRepo` produced '' and the
/// callers' `File(...).existsSync()` came back false — which their guards
/// then reported as "the artefact was not built". Losing the repository and
/// not having built anything are different problems, and only one of them is
/// a legitimate skip.
String repoRoot() {
  final String? declared = Platform.environment['DOVETAIL_REPO_ROOT'];
  if (declared != null && declared.isNotEmpty) {
    if (!_looksLikeRoot(Directory(declared))) {
      throw StateError(
        'DOVETAIL_REPO_ROOT is "$declared", which has no toolkit/ in it.',
      );
    }
    return Directory(declared).absolute.path;
  }

  Directory here = Directory.current.absolute;
  for (int step = 0; step < 6; step++) {
    if (_looksLikeRoot(here)) {
      return here.path;
    }
    final Directory parent = here.parent;
    if (parent.path == here.path) {
      break;
    }
    here = parent;
  }

  throw StateError(
    'no repository root above ${Directory.current.path}. Run this through '
    'the repository esteira, or set DOVETAIL_REPO_ROOT to the checkout.',
  );
}

/// An absolute path to [segments] under [repoRoot].
String inRepo(List<String> segments) =>
    p.joinAll(<String>[repoRoot(), ...segments]);

bool _looksLikeRoot(Directory candidate) =>
    Directory(p.join(candidate.path, 'toolkit')).existsSync();
