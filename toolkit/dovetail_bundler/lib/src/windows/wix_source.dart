import 'package:dovetail_bundler/src/spec/install_mode.dart';
import 'package:dovetail_bundler/src/windows/msi_component_tree.dart';
import 'package:dovetail_bundler/src/windows/msi_privileged_step.dart';
import 'package:dovetail_bundler/src/windows/msi_spec.dart';
import 'package:dovetail_bundler/src/windows/wix_text.dart';

abstract final class WixSource {
  static const String schema = 'http://wixtoolset.org/schemas/v4/wxs';

  static String render(MsiSpec spec, MsiComponentTree tree) {
    final List<String> lines = <String>[
      '<?xml version="1.0" encoding="utf-8"?>',
      '<Wix xmlns="$schema">',
      ..._package(spec, tree),
      '</Wix>',
      '',
    ];
    return lines.join('\n');
  }

  static List<String> _package(MsiSpec spec, MsiComponentTree tree) {
    final String scope = spec.bundle.installMode == InstallMode.perMachine
        ? 'perMachine'
        : 'perUser';

    return <String>[
      '  <Package',
      '    Name="${WixText.attribute(spec.bundle.productName)}"',
      '    Manufacturer="${WixText.attribute(spec.bundle.manufacturer)}"',
      '    Version="${spec.productVersion}"',
      '    UpgradeCode="${spec.normalizedUpgradeCode}"',
      '    Scope="$scope"',
      '    InstallerVersion="500"',
      '    Compressed="yes"',
      '    Codepage="1252">',
      '',
      '    <MajorUpgrade',
      '      AllowDowngrades="${spec.allowDowngrades ? 'yes' : 'no'}"',
      if (!spec.allowDowngrades)
        '      DowngradeErrorMessage="A newer version of '
            '${WixText.attribute(spec.bundle.productName)} is already '
            'installed."',
      '      Schedule="afterInstallInitialize" />',
      '',
      '    <MediaTemplate EmbedCab="yes" />',
      '',
      ..._conflictGuards(spec),
      ..._directories(spec, tree),
      '',
      ..._feature(tree),
      '',
      ..._customActions(spec, tree),
      '  </Package>',
    ];
  }

  static List<String> _conflictGuards(MsiSpec spec) {
    if (spec.conflictingRegistryKeys.isEmpty) {
      return const <String>[];
    }

    final List<String> lines = <String>[];
    final List<String> properties = <String>[];
    for (int index = 0; index < spec.conflictingRegistryKeys.length; index++) {
      final String property = 'FOREIGNINSTALL$index';
      properties.add(property);
      lines.addAll(<String>[
        '    <Property Id="$property">',
        '      <RegistrySearch',
        '        Id="search$property"',
        '        Root="HKLM"',
        '        Key="${WixText.attribute(spec.conflictingRegistryKeys[index])}"',
        '        Name="UninstallString"',
        '        Type="raw"',
        '        Bitness="always64" />',
        '    </Property>',
      ]);
    }

    final String condition = properties
        .map((String property) => 'NOT $property')
        .join(' AND ');

    lines.addAll(<String>[
      '    <Launch',
      '      Condition="$condition"',
      '      Message="Another installer already registered '
          '${WixText.attribute(spec.bundle.productName)} on this machine. '
          'Uninstall it first: two installers registering one privileged '
          'service leaves both unable to remove it." />',
      '',
    ]);
    return lines;
  }

  static List<String> _directories(MsiSpec spec, MsiComponentTree tree) {
    final List<String> lines = <String>[
      '    <StandardDirectory Id="${_rootFolderFor(spec)}">',
      '      <Directory Id="INSTALLFOLDER" '
          'Name="${WixText.attribute(spec.bundle.productName)}">',
      ..._componentsOf(tree, 'INSTALLFOLDER', 8),
      ..._childDirectories(tree, null, 8),
      '      </Directory>',
      '    </StandardDirectory>',
    ];
    return lines;
  }

  static String _rootFolderFor(MsiSpec spec) =>
      spec.bundle.installMode == InstallMode.perMachine
      ? 'ProgramFiles64Folder'
      : 'LocalAppDataFolder';

  static List<String> _childDirectories(
    MsiComponentTree tree,
    String? parentRelativePath,
    int indent,
  ) {
    final String pad = ' ' * indent;
    final List<String> lines = <String>[];
    for (final MsiDirectory directory in tree.childrenOf(parentRelativePath)) {
      lines.addAll(<String>[
        '$pad<Directory Id="${directory.id}" '
            'Name="${WixText.attribute(directory.name)}">',
        ..._componentsOf(tree, directory.id, indent + 2),
        ..._childDirectories(tree, directory.relativePath, indent + 2),
        '$pad</Directory>',
      ]);
    }
    return lines;
  }

  static List<String> _componentsOf(
    MsiComponentTree tree,
    String directoryId,
    int indent,
  ) {
    final String pad = ' ' * indent;
    final List<String> lines = <String>[];
    for (final MsiComponent component in tree.componentsIn(directoryId)) {
      lines.addAll(<String>[
        '$pad<Component Id="${component.id}" Guid="${component.guid}">',
        '$pad  <File',
        '$pad    Id="${component.fileId}"',
        '$pad    Name="${WixText.attribute(component.fileName)}"',
        '$pad    Source="\$(var.StageDir)\\'
            '${WixText.attribute(component.windowsRelativePath)}"',
        '$pad    KeyPath="yes" />',
        '$pad</Component>',
      ]);
    }
    return lines;
  }

  static List<String> _feature(MsiComponentTree tree) => <String>[
    '    <Feature Id="Main" Title="Application" Level="1">',
    for (final MsiComponent component in tree.components)
      '      <ComponentRef Id="${component.id}" />',
    '    </Feature>',
  ];

  static List<String> _customActions(MsiSpec spec, MsiComponentTree tree) {
    if (spec.steps.isEmpty) {
      return const <String>[];
    }

    final List<String> definitions = <String>[];
    final List<String> sequence = <String>[];

    for (final MsiPrivilegedStep step in _ordered(spec)) {
      final MsiComponent? host = tree.componentFor(step.relativeExecutable);
      if (host == null) {
        throw StateError(
          'privileged step ${step.id} points at '
          '${step.relativeExecutable}, which the staged tree does not hold',
        );
      }

      definitions.addAll(<String>[
        '    <CustomAction',
        '      Id="${step.id}"',
        '      FileRef="${host.fileId}"',
        '      ExeCommand="${WixText.attribute(step.commandLine)}"',
        '      Execute="${step.isRollback ? 'rollback' : 'deferred'}"',
        '      Impersonate="no"',
        '      Return="${step.fatalOnFailure ? 'check' : 'ignore'}" />',
      ]);

      sequence.add(
        '      <Custom Action="${step.id}" '
        '${step.phase.sequenceAttribute}="${step.phase.anchor}" />',
      );
    }

    return <String>[
      ...definitions,
      '',
      '    <InstallExecuteSequence>',
      ...sequence,
      '    </InstallExecuteSequence>',
    ];
  }

  static List<MsiPrivilegedStep> _ordered(MsiSpec spec) {
    final List<MsiPrivilegedStep> rollbacks = spec.steps
        .where((MsiPrivilegedStep step) => step.isRollback)
        .toList(growable: false);
    final List<MsiPrivilegedStep> work = spec.steps
        .where((MsiPrivilegedStep step) => !step.isRollback)
        .toList(growable: false);
    return <MsiPrivilegedStep>[...rollbacks, ...work];
  }
}
