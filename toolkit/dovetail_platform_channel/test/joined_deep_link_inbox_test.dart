import 'dart:async';

import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeInbox implements DeepLinkInbox {
  _FakeInbox({this.initial});

  final Uri? initial;
  final StreamController<Uri> controller = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> initialLink() async => initial;

  @override
  Stream<Uri> links() => controller.stream;
}

ForwardedLaunch launchWith(List<String> arguments) =>
    ForwardedLaunch(workingDirectory: '/tmp', arguments: arguments);

void main() {
  group('the urls hidden in a forwarded launch', () {
    test('an argument with a scheme should be found', () {
      expect(
        LaunchArguments.urisIn(<String>[
          '/opt/demo/demo',
          'demo://connect?server=br-1',
        ]).map((Uri uri) => uri.toString()),
        <String>['demo://connect?server=br-1'],
      );
    });

    test('a plain path should not be read as a url', () {
      expect(
        LaunchArguments.urisIn(<String>['/opt/demo/demo', '--verbose']),
        isEmpty,
        reason:
            'every second launch carries the executable path, and treating it '
            'as a deep link would open the app on itself',
      );
    });

    test('a file url should be ignored', () {
      expect(
        LaunchArguments.urisIn(<String>['file:///etc/passwd']),
        isEmpty,
        reason:
            'a second process can be launched with any argument, and file:// '
            'is how a local path arrives dressed as a link',
      );
    });

    test('a scheme filter should keep only what the app registered', () {
      expect(
        LaunchArguments.urisIn(
          <String>['demo://connect', 'https://example.com/phish'],
          schemes: <String>{'demo'},
        ).map((Uri uri) => uri.scheme),
        <String>['demo'],
        reason:
            'the app registers its own scheme with the system, and an https '
            'url in argv came from somewhere that is not that registration',
      );
    });

    test('several links in one launch should all come through', () {
      expect(
        LaunchArguments.urisIn(<String>[
          'demo://a',
          'demo://b',
        ]).map((Uri uri) => uri.host),
        <String>['a', 'b'],
      );
    });
  });

  group('the joined inbox', () {
    late _FakeInbox platform;
    late StreamController<ForwardedLaunch> launches;
    late JoinedDeepLinkInbox joined;

    setUp(() {
      platform = _FakeInbox(initial: Uri.parse('demo://cold-start'));
      launches = StreamController<ForwardedLaunch>.broadcast();
      joined = JoinedDeepLinkInbox(
        inbox: platform,
        launches: launches.stream,
        schemes: <String>{'demo'},
      );
    });

    tearDown(() async {
      await joined.dispose();
      await launches.close();
      await platform.controller.close();
    });

    test('a link from the platform should arrive', () async {
      final Future<Uri> first = joined.links().first;

      platform.controller.add(Uri.parse('demo://from-platform'));

      expect(
        (await first.timeout(const Duration(seconds: 3))).host,
        'from-platform',
      );
    });

    test('a link from a second process should arrive too', () async {
      final Future<Uri> first = joined.links().first;

      launches.add(launchWith(<String>['/opt/demo/demo', 'demo://forwarded']));

      expect(
        (await first.timeout(const Duration(seconds: 3))).host,
        'forwarded',
        reason:
            'on macOS and Linux a url opened while the app is running reaches '
            'the guard, and the inbox was a separate stream nobody joined, so '
            'a consumer listening to links() never saw it',
      );
    });

    test('both sources should reach one listener', () async {
      final Future<List<Uri>> collected = joined.links().take(2).toList();

      platform.controller.add(Uri.parse('demo://one'));
      launches.add(launchWith(<String>['demo://two']));

      final List<Uri> seen = await collected.timeout(
        const Duration(seconds: 3),
      );

      expect(seen.map((Uri uri) => uri.host).toSet(), <String>{'one', 'two'});
    });

    test('the cold-start link should still come from the platform', () async {
      expect((await joined.initialLink())!.host, 'cold-start');
    });

    test('a forwarded launch carrying no url should publish nothing', () async {
      final Future<Uri> first = joined.links().first;

      launches.add(launchWith(<String>['/opt/demo/demo', '--minimised']));
      platform.controller.add(Uri.parse('demo://after'));

      expect((await first.timeout(const Duration(seconds: 3))).host, 'after');
    });

    test('nothing should be published after dispose', () async {
      await joined.dispose();

      expect(
        () => launches.add(launchWith(<String>['demo://late'])),
        returnsNormally,
      );
    });
  });
}
