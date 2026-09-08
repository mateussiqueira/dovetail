import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/spec/bundle_spec.dart';
import 'package:dovetail_bundler/src/spec/install_mode.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:dovetail_bundler/src/windows/msi_component_guid.dart';
import 'package:dovetail_bundler/src/windows/msi_privileged_step.dart';
import 'package:dovetail_bundler/src/windows/msi_version.dart';

final class MsiSpec {
  MsiSpec({
    required this.bundle,
    required this.upgradeCode,
    required this.arch,
    this.steps = const <MsiPrivilegedStep>[],
    this.cultures = const <String>['en-US'],
    this.allowDowngrades = false,
    this.conflictingRegistryKeys = const <String>[],
  }) {
    MsiComponentGuid.forPath(upgradeCode: upgradeCode, relativePath: 'probe');
    if (bundle.installMode != InstallMode.perMachine && _hasPrivilegedStep) {
      throw const BundleFailure(
        'A per-user MSI cannot run a privileged step.',
        remedy:
            'A deferred custom action with Impersonate="no" needs an elevated '
            'install. Either build this MSI per-machine, or drop the step.',
      );
    }
    _refuseDuplicateStepIds();
    _refuseOrphanRollback();
  }

  final BundleSpec bundle;
  final String upgradeCode;
  final TargetArch arch;
  final List<MsiPrivilegedStep> steps;
  final List<String> cultures;
  final bool allowDowngrades;
  final List<String> conflictingRegistryKeys;

  String get productVersion => MsiVersion.of(bundle.version);

  String get msiFileName =>
      '${bundle.mainBinaryName}_${bundle.version.semantic}_${arch.wix}.msi';

  String get normalizedUpgradeCode =>
      upgradeCode.trim().replaceAll('{', '').replaceAll('}', '').toUpperCase();

  List<MsiPrivilegedStep> stepsFor(MsiPhase phase) => steps
      .where((MsiPrivilegedStep step) => step.phase == phase)
      .toList(growable: false);

  bool get _hasPrivilegedStep => steps.isNotEmpty;

  void _refuseDuplicateStepIds() {
    final Set<String> seen = <String>{};
    for (final MsiPrivilegedStep step in steps) {
      if (!seen.add(step.id)) {
        throw BundleFailure(
          'Two privileged steps share the id "${step.id}".',
          remedy: 'A custom action id is a primary key in the MSI database.',
        );
      }
    }
  }

  void _refuseOrphanRollback() {
    final Set<String> ids = steps.map((MsiPrivilegedStep s) => s.id).toSet();
    for (final MsiPrivilegedStep step in steps.where(
      (MsiPrivilegedStep s) => s.isRollback,
    )) {
      if (!ids.contains(step.rollbackFor)) {
        throw BundleFailure(
          'Rollback step "${step.id}" undoes "${step.rollbackFor}", which '
          'this spec does not declare.',
          remedy:
              'A rollback action that is scheduled without the action it '
              'undoes leaves the machine in the state nobody cleans up.',
        );
      }
    }
  }
}
