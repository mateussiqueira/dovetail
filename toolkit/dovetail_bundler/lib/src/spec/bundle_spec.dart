import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:dovetail_bundler/src/spec/app_version.dart';
import 'package:dovetail_bundler/src/spec/install_mode.dart';
import 'package:dovetail_bundler/src/spec/staged_file.dart';

final class BundleSpec {
  BundleSpec({
    required this.productName,
    required this.manufacturer,
    required this.identifier,
    required this.version,
    required this.mainBinaryName,
    required this.appDirectory,
    required this.outputDirectory,
    this.installMode = InstallMode.perMachine,
    this.installerHooks,
    this.installerIcon,
    this.licenseFile,
    this.homepage,
    this.extraFiles = const <StagedFile>[],
    this.installerLanguages = const <String>['English'],
    this.minimumSystemVersion,
  }) {
    if (productName.trim().isEmpty) {
      throw const BundleFailure('productName is empty.');
    }
    if (mainBinaryName.trim().isEmpty) {
      throw const BundleFailure('mainBinaryName is empty.');
    }
    if (installerLanguages.isEmpty) {
      throw const BundleFailure(
        'the installer declares no language.',
        remedy:
            'An NSIS installer with no MUI_LANGUAGE fails to compile. Name at '
            'least one.',
      );
    }
    final Set<String> languages = <String>{};
    for (final String language in installerLanguages) {
      if (language.trim().isEmpty) {
        throw const BundleFailure('an installer language is blank.');
      }
      if (!languages.add(language)) {
        throw BundleFailure(
          'the installer language "$language" is declared twice.',
          remedy: 'NSIS refuses a repeated MUI_LANGUAGE.',
        );
      }
    }
    if (!identifier.contains('.')) {
      throw BundleFailure(
        'identifier "$identifier" is not a reverse-domain name.',
        remedy: 'Write it as com.example.app.',
      );
    }
  }

  final String productName;
  final String manufacturer;
  final String identifier;
  final AppVersion version;
  final String mainBinaryName;
  final String appDirectory;
  final String outputDirectory;
  final InstallMode installMode;
  final String? installerHooks;
  final String? installerIcon;
  final String? licenseFile;
  final String? homepage;
  final List<StagedFile> extraFiles;
  final List<String> installerLanguages;
  final String? minimumSystemVersion;

  bool get offersLanguageChoice => installerLanguages.length > 1;

  String installerFileNameFor(TargetArch arch) =>
      '${mainBinaryName}_${version.semantic}_${arch.wix}_setup.exe';
}
