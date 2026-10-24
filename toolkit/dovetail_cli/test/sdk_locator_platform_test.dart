import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final p.Context windows = p.Context(style: p.Style.windows);
  final p.Context posix = p.Context(style: p.Style.posix);
  final Map<String, String> environment = <String, String>{
    'LOCALAPPDATA': r'C:\Users\Windows User\AppData\Local',
    'USERPROFILE': r'C:\Users\Windows User',
    'HOME': '/shell/home',
  };

  test(
    'Windows SDK root uses local application data with Windows separators',
    () {
      expect(
        SdkLocator(context: windows, environment: environment).home,
        r'C:\Users\Windows User\AppData\Local\dovetail',
      );
    },
  );

  test('POSIX SDK root preserves HOME despite LOCALAPPDATA being set', () {
    expect(
      SdkLocator(context: posix, environment: environment).home,
      '/shell/home/.dovetail',
    );
  });

  test(
    'explicit SDK root wins over application data and environment override',
    () {
      expect(
        SdkLocator(
          home: r'D:\Explicit SDK',
          context: windows,
          environment: <String, String>{
            ...environment,
            'DOVETAIL_HOME': r'E:\Other SDK',
          },
        ).home,
        r'D:\Explicit SDK',
      );
    },
  );

  test('environment SDK override wins over Windows local application data', () {
    expect(
      SdkLocator(
        context: windows,
        environment: <String, String>{
          ...environment,
          'DOVETAIL_HOME': r'E:\Other SDK',
        },
      ).home,
      r'E:\Other SDK',
    );
  });

  for (final String? local in <String?>[null, '']) {
    test(
      'missing or empty LOCALAPPDATA preserves the legacy SDK location ($local)',
      () {
        expect(
          SdkLocator(
            context: windows,
            environment: <String, String>{
              'USERPROFILE': r'C:\Users\Windows User',
              'LOCALAPPDATA': ?local,
            },
          ).home,
          r'C:\Users\Windows User\.dovetail',
        );
      },
    );
  }
}
