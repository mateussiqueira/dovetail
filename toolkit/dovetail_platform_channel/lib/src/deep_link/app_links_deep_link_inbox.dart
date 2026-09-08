import 'package:app_links/app_links.dart';
import 'package:dovetail_platform_channel/src/deep_link/deep_link_inbox.dart';

final class AppLinksDeepLinkInbox implements DeepLinkInbox {
  AppLinksDeepLinkInbox({AppLinks? links}) : _links = links ?? AppLinks();

  final AppLinks _links;

  @override
  Future<Uri?> initialLink() => _links.getInitialLink();

  @override
  Stream<Uri> links() => _links.uriLinkStream;
}
