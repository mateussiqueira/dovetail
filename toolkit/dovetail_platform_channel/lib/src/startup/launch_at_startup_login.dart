import 'package:dovetail_platform_channel/src/startup/launch_at_login.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

final class LaunchAtStartupLogin implements LaunchAtLogin {
  LaunchAtStartupLogin({LaunchAtStartup? delegate})
    : _delegate = delegate ?? launchAtStartup;

  final LaunchAtStartup _delegate;

  void configure({
    required String appName,
    required String appPath,
    String? packageName,
    List<String> args = const <String>[],
  }) => _delegate.setup(
    appName: appName,
    appPath: appPath,
    packageName: packageName,
    args: args,
  );

  @override
  Future<bool> isEnabled() => _delegate.isEnabled();

  @override
  Future<void> enable() => _delegate.enable();

  @override
  Future<void> disable() => _delegate.disable();
}
