import 'package:dovetail_platform_channel/src/open/external_opener.dart';
import 'package:url_launcher/url_launcher.dart';

final class UrlLauncherOpener implements ExternalOpener {
  const UrlLauncherOpener();

  @override
  Future<bool> canOpenUrl(Uri url) => canLaunchUrl(url);

  @override
  Future<bool> openUrl(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}
