final class NotificationsUnavailable implements Exception {
  const NotificationsUnavailable(this.because);

  final String because;

  @override
  String toString() =>
      'the notification service could not be initialised on this session, so '
      'nothing can be shown through it: $because';
}
