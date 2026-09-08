abstract interface class BundleInfo {
  Future<String> appName();
  Future<String> version();
  Future<String> buildNumber();
  Future<String> packageName();
}
