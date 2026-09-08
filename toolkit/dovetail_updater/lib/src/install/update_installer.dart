import 'package:dovetail_updater/src/flow/verified_artifact.dart';

enum InstallOutcome { installedRestartNeeded, installerLaunchedAppMustExit }

abstract interface class UpdateInstaller {
  Future<InstallOutcome> install(VerifiedArtifact artifact);
}
