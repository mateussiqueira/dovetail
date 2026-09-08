import 'package:dovetail_platform_channel/src/notify/system_notice.dart';

abstract interface class SystemNotifier {
  Future<void> show(SystemNotice notice);
  Future<void> cancel(int id);
  Future<void> cancelAll();
}
