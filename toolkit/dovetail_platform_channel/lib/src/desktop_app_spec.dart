import 'package:dovetail_platform_channel/src/window/window_spec.dart';

final class DesktopAppSpec {
  const DesktopAppSpec({
    required this.window,
    required this.applicationId,
    required this.displayName,
    required this.notificationGuid,
    this.executablePath,
    this.launchArguments = const <String>[],
    this.stateDirectory,
  });

  final WindowSpec window;
  final String applicationId;
  final String displayName;
  final String notificationGuid;
  final String? executablePath;
  final List<String> launchArguments;
  final String? stateDirectory;

  bool get remembersPlacement => stateDirectory != null;
}
