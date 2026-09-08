import 'package:dovetail_platform_channel/src/instance/forwarded_launch.dart';
import 'package:dovetail_platform_channel/src/instance/single_instance_verdict.dart';

abstract interface class SingleInstance {
  Future<SingleInstanceVerdict> claim({
    List<String> arguments,
    String? workingDirectory,
  });

  Stream<ForwardedLaunch> launches();

  Future<void> release();

  Future<void> dispose();
}
