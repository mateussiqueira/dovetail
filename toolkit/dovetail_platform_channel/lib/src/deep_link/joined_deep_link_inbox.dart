import 'dart:async';

import 'package:async/async.dart';

import 'package:dovetail_platform_channel/src/deep_link/deep_link_inbox.dart';
import 'package:dovetail_platform_channel/src/deep_link/launch_arguments.dart';
import 'package:dovetail_platform_channel/src/instance/forwarded_launch.dart';

final class JoinedDeepLinkInbox implements DeepLinkInbox {
  JoinedDeepLinkInbox({
    required this.inbox,
    required Stream<ForwardedLaunch> launches,
    this.schemes = const <String>{},
  }) {
    _forwarded = launches.listen(_onLaunch);
  }

  final DeepLinkInbox inbox;
  final Set<String> schemes;
  final StreamController<Uri> _fromLaunches = StreamController<Uri>.broadcast();
  late final StreamSubscription<ForwardedLaunch> _forwarded;

  @override
  Future<Uri?> initialLink() => inbox.initialLink();

  @override
  Stream<Uri> links() =>
      StreamGroup.merge(<Stream<Uri>>[inbox.links(), _fromLaunches.stream]);

  Future<void> dispose() async {
    await _forwarded.cancel();
    await _fromLaunches.close();
  }

  void _onLaunch(ForwardedLaunch launch) {
    if (_fromLaunches.isClosed) {
      return;
    }
    for (final Uri uri in LaunchArguments.urisIn(
      launch.arguments,
      schemes: schemes,
    )) {
      _fromLaunches.add(uri);
    }
  }
}
