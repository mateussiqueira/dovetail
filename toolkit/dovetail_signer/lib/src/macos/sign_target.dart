import 'package:path/path.dart' as p;

final class SignTarget {
  const SignTarget({required this.path, required this.isExecutable});

  final String path;
  final bool isExecutable;

  @override
  bool operator ==(Object other) =>
      other is SignTarget &&
      other.path == path &&
      other.isExecutable == isExecutable;

  @override
  int get hashCode => Object.hash(path, isExecutable);

  @override
  String toString() => 'SignTarget($path, executable: $isExecutable)';
}

const Set<String> _nestedCodeFolders = <String>{
  'macos',
  'frameworks',
  'plugins',
  'helpers',
  'xpcservices',
  'libraries',
  'extensions',
};

const String _libraryFolder = 'library';

const Set<String> _nestedBundleExtensions = <String>{
  '.app',
  '.appex',
  '.xpc',
  '.systemextension',
};

const Set<String> _libraryExtensions = <String>{'.dylib', '.so', '.a'};

abstract final class SignOrder {
  static List<SignTarget> insideOut({
    required String bundlePath,
    required List<String> contents,
  }) {
    final String contentsRoot = p.join(bundlePath, 'Contents');
    final List<SignTarget> nested = <SignTarget>[];

    for (final String entry in contents) {
      if (!isNestedCode(entry, contentsRoot: contentsRoot)) {
        continue;
      }
      if (_nestedBundleExtensions.contains(p.extension(entry).toLowerCase())) {
        nested.addAll(insideOut(bundlePath: entry, contents: contents));
        continue;
      }
      nested.add(SignTarget(path: entry, isExecutable: _isExecutable(entry)));
    }

    nested.sort((SignTarget a, SignTarget b) {
      final int byDepth = _depth(b.path).compareTo(_depth(a.path));
      return byDepth != 0 ? byDepth : a.path.compareTo(b.path);
    });

    return <SignTarget>[
      ...nested,
      SignTarget(path: bundlePath, isExecutable: true),
    ];
  }

  static bool isNestedCode(String entry, {required String contentsRoot}) {
    if (!p.isWithin(contentsRoot, entry)) {
      return false;
    }
    final List<String> segments = p.split(
      p.relative(entry, from: contentsRoot),
    );
    if (segments.length == 2) {
      return isNestedCodeFolder(segments.first);
    }
    if (segments.length == 3) {
      return segments.first.toLowerCase() == _libraryFolder;
    }
    return false;
  }

  static bool isNestedCodeFolder(String folderName) =>
      _nestedCodeFolders.contains(folderName.toLowerCase());

  static bool _isExecutable(String entry) {
    final String extension = p.extension(entry).toLowerCase();
    if (_libraryExtensions.contains(extension) || extension == '.framework') {
      return false;
    }
    return true;
  }

  static int _depth(String path) => p.split(path).length;
}
