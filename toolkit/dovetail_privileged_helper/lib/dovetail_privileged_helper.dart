export 'package:dovetail_privileged_helper/src/approval_pane.dart';
export 'package:dovetail_privileged_helper/src/darwin/darwin_daemon_helper.dart';
export 'package:dovetail_privileged_helper/src/darwin/darwin_helper_route.dart';
export 'package:dovetail_privileged_helper/src/darwin/darwin_service_status.dart';
export 'package:dovetail_privileged_helper/src/helper_backend.dart';
export 'package:dovetail_privileged_helper/src/helper_host.dart';
export 'package:dovetail_privileged_helper/src/helper_spec.dart';
export 'package:dovetail_privileged_helper/src/helper_state.dart';
export 'package:dovetail_privileged_helper/src/helper_status.dart';
export 'package:dovetail_privileged_helper/src/helper_watch.dart';
export 'package:dovetail_privileged_helper/src/linux/systemd_unit_state.dart';
// `SystemdHelper` is deliberately not here, and `SystemdUnitState` above is.
// The reading of systemd's answer is the part a consumer has any reason to
// name; the helper itself carries a `ProcessRunner` in its signature, from
// `dovetail_process_runner`, which nobody depending on this package declares.
// The package next door shipped that mistake once — a class whose default
// argument named a type the consumer could not resolve, so merely writing the
// constructor produced "Undefined class". `PrivilegedHelpers.of` returns the
// helper behind the interface, which is how it is meant to be reached.
export 'package:dovetail_privileged_helper/src/privileged_helper.dart';
export 'package:dovetail_privileged_helper/src/privileged_helpers.dart';
export 'package:dovetail_privileged_helper/src/registration_guard.dart';
export 'package:dovetail_privileged_helper/src/unsupported_helper.dart';
export 'package:dovetail_privileged_helper/src/windows/windows_service_control.dart';
export 'package:dovetail_privileged_helper/src/windows/windows_service_helper.dart';
export 'package:dovetail_privileged_helper/src/windows/windows_service_status.dart';
