import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:test/test.dart';

void main() {
  test('parse should accept major.minor.patch', () {
    final AppVersion sut = AppVersion.parse('1.2.3');

    expect(sut.semantic, '1.2.3');
    expect(sut.windowsFileVersion, '1.2.3.0');
  });

  test('parse should accept a leading v', () {
    expect(AppVersion.parse('v0.1.0').semantic, '0.1.0');
  });

  test('parse should carry a numeric build into the windows file version', () {
    final AppVersion sut = AppVersion.parse('1.2.3+47');

    expect(sut.windowsFileVersion, '1.2.3.47');
    expect(sut.toString(), '1.2.3+47');
  });

  test(
    'parse should refuse non-numeric build metadata instead of zeroing it',
    () {
      expect(
        () => AppVersion.parse('1.2.3+abc'),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.message,
            'message',
            contains('non-numeric build metadata'),
          ),
        ),
      );
    },
  );

  test('parse should refuse a version that is not three numbers', () {
    for (final String raw in <String>['1.2', '1', 'x.y.z', '', '1.2.3.4']) {
      expect(
        () => AppVersion.parse(raw),
        throwsA(isA<BundleFailure>()),
        reason: raw,
      );
    }
  });

  test('a failure should carry a remedy the operator can act on', () {
    try {
      AppVersion.parse('1.2.3+abc');
      fail('expected a BundleFailure');
    } on BundleFailure catch (failure) {
      expect(failure.remedy, isNotNull);
      expect(failure.toString(), contains(failure.remedy!));
    }
  });
}
