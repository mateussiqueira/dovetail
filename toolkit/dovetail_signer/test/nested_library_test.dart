import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _bundle = '/build/Example.app';

String at(List<String> segments) =>
    p.joinAll(<String>[_bundle, 'Contents', ...segments]);

List<String> pathsOf(List<String> contents) => SignOrder.insideOut(
  bundlePath: _bundle,
  contents: contents,
).map((SignTarget target) => target.path).toList();

List<String> nestedOf(List<String> contents) =>
    pathsOf(contents).where((String path) => path != _bundle).toList();

void main() {
  group('the code Apple puts under Contents/Library', () {
    test('a login item should be reached', () {
      final String helper = at(<String>[
        'Library',
        'LoginItems',
        'Launcher.app',
      ]);

      expect(
        pathsOf(<String>[
          helper,
          at(<String>['MacOS', 'Example']),
        ]),
        contains(helper),
        reason:
            'the bundle seal covers every Mach-O inside it, so a login item '
            'left unsigned makes Gatekeeper refuse the whole application',
      );
    });

    test('a privileged helper should be reached', () {
      final String helper = at(<String>[
        'Library',
        'LaunchServices',
        'com.example.helper',
      ]);

      expect(pathsOf(<String>[helper]), contains(helper));
    });

    test('a system extension should be reached', () {
      final String extension = at(<String>[
        'Library',
        'SystemExtensions',
        'com.example.tunnel.systemextension',
      ]);

      expect(pathsOf(<String>[extension]), contains(extension));
    });

    test('the folder itself is not code', () {
      expect(
        nestedOf(<String>[
          at(<String>['Library']),
        ]),
        isEmpty,
      );
    });

    test('a resource four levels down should not be signed on its own', () {
      expect(
        nestedOf(<String>[
          at(<String>['Library', 'LoginItems', 'Launcher.app', 'Contents']),
        ]),
        isEmpty,
        reason:
            'the nested bundle is signed as a bundle; signing a path inside '
            'it separately is what breaks its own seal',
      );
    });
  });

  group('the folders that were already reached', () {
    test('a framework should still be found', () {
      final String framework = at(<String>[
        'Frameworks',
        'FlutterMacOS.framework',
      ]);

      expect(pathsOf(<String>[framework]), contains(framework));
    });

    test('the capital I in PlugIns should still match', () {
      final String plugin = at(<String>['PlugIns', 'Thing.bundle']);

      expect(
        pathsOf(<String>[plugin]),
        contains(plugin),
        reason:
            'APFS is case-insensitive and Dart string comparison is not, so '
            'the folder name has to be matched case-insensitively',
      );
    });
  });

  group('the order it signs in', () {
    test('the deepest thing should come first and the app last', () {
      final List<String> order = pathsOf(<String>[
        at(<String>['MacOS', 'Example']),
        at(<String>['Library', 'LoginItems', 'Launcher.app']),
        at(<String>['Frameworks', 'Core.framework']),
      ]);

      expect(
        order.first,
        contains('Library/LoginItems'),
        reason:
            'signing outside-in re-seals the outer bundle before the inner '
            'one changes, and the outer seal then no longer matches',
      );
      expect(
        order.last,
        _bundle,
        reason: 'the bundle seals its own contents, so it is signed last',
      );
      expect(
        order[order.length - 2],
        endsWith('Contents/MacOS/Example'),
        reason: 'and the main executable immediately before it',
      );
    });
  });
}
