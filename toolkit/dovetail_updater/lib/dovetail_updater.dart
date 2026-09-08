export 'package:dovetail_updater/src/endpoint/endpoint_template.dart';
export 'package:dovetail_updater/src/fetch/artifact_fetcher.dart';
export 'package:dovetail_updater/src/fetch/http_artifact_fetcher.dart';
export 'package:dovetail_updater/src/flow/update_flow.dart';
export 'package:dovetail_updater/src/flow/verified_artifact.dart';
export 'package:dovetail_updater/src/install/installer_for_host.dart';
export 'package:dovetail_updater/src/install/linux_installer.dart';
export 'package:dovetail_updater/src/install/linux_package_format.dart';
export 'package:dovetail_updater/src/install/macos_installer.dart';
export 'package:dovetail_updater/src/install/update_installer.dart';
export 'package:dovetail_updater/src/install/windows_installer.dart';
export 'package:dovetail_updater/src/manifest/manifest_parser.dart';
export 'package:dovetail_updater/src/manifest/manifest_writer.dart';
export 'package:dovetail_updater/src/manifest/platform_key.dart';
export 'package:dovetail_updater/src/manifest/platform_release.dart';
export 'package:dovetail_updater/src/manifest/update_manifest.dart';
export 'package:dovetail_updater/src/minisign/minisign_public_key.dart';
export 'package:dovetail_updater/src/minisign/minisign_signature.dart';
export 'package:dovetail_updater/src/minisign/minisign_verifier.dart';
export 'package:dovetail_updater/src/policy/downgrade_refused.dart';
export 'package:dovetail_updater/src/policy/update_decision.dart';
export 'package:dovetail_updater/src/policy/update_policy.dart';
export 'package:dovetail_updater/src/update_failure.dart';
export 'package:dovetail_process_runner/dovetail_process_runner.dart';
// `Version` esta na assinatura publica de UpdateManifest, ManifestParser,
// ManifestWriter e DowngradeRefused — e vinha do pub_semver, que nenhum
// consumidor declara. Quem importa so `package:dovetail/dovetail.dart` recebia
// "The function 'Version' isn't defined" ao tocar o updater. Reexportado com
// `show`: so o tipo que a API ja expoe, nao o pacote inteiro.
export 'package:pub_semver/pub_semver.dart' show Version;
