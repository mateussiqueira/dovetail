import 'dart:io';

import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';

import 'support/repo_root.dart';

String _read(List<String> segments) =>
    File(inRepo(segments)).readAsStringSync();

void main() {
  late String buildSdk;
  late String release;
  late String proveBridge;
  late String proveSdk;

  setUpAll(() {
    buildSdk = _read(<String>['tool', 'build_sdk.sh']);
    release = _read(<String>['tool', 'release.sh']);
    proveBridge = _read(<String>['tool', 'ci', 'prove_bridge.sh']);
    proveSdk = _read(<String>['tool', 'ci', 'prove_sdk.sh']);
  });

  test('the SDK tarball should not carry weave_di, so no override in a '
      'generated app shadows the one on pub.dev', () {
    expect(buildSdk, isNot(contains('packages/weave_di')));
  });

  test('no build or release script should look for a weave_di checkout', () {
    expect(buildSdk, isNot(contains('DOVETAIL_WEAVE_PATH')));
    expect(release, isNot(contains('DOVETAIL_WEAVE_PATH')));
    expect(proveBridge, isNot(contains('DOVETAIL_WEAVE_PATH')));
  });

  test('the bridge canary should scaffold with options new still has', () {
    expect(NewCommand().argParser.options, isNot(contains('weave-path')));
    expect(proveBridge, isNot(contains('--weave-path')));
  });

  test('the SDK canary should prove weave_di resolves hosted from pub.dev, '
      'then analyze and test the app', () {
    expect(proveSdk, contains('grep -q weave_di pubspec_overrides.yaml'));
    expect(proveSdk, contains('if [ "\$weave_source" != "hosted" ]; then'));
    expect(proveSdk, contains('flutter analyze'));
    expect(proveSdk, contains('flutter test'));
  });
}
