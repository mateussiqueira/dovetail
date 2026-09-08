import 'package:dovetail_platform_channel/src/bundle/bundle_info.dart';
import 'package:package_info_plus/package_info_plus.dart';

final class PackageInfoBundle implements BundleInfo {
  PackageInfoBundle();

  Future<PackageInfo>? _pending;

  Future<PackageInfo> _info() => _pending ??= PackageInfo.fromPlatform();

  @override
  Future<String> appName() async => (await _info()).appName;

  @override
  Future<String> version() async => (await _info()).version;

  @override
  Future<String> buildNumber() async => (await _info()).buildNumber;

  @override
  Future<String> packageName() async => (await _info()).packageName;
}
