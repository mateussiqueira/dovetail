import 'package:pub_semver/pub_semver.dart';

enum UpdateAvailability { upToDate, available }

final class UpdateDecision {
  const UpdateDecision._(this.availability, this.reason, this.offered);

  const UpdateDecision.upToDate(String reason)
    : this._(UpdateAvailability.upToDate, reason, null);

  const UpdateDecision.available(Version offered)
    : this._(
        UpdateAvailability.available,
        'a newer version is offered',
        offered,
      );

  final UpdateAvailability availability;
  final String reason;
  final Version? offered;

  bool get shouldUpdate => availability == UpdateAvailability.available;
}
