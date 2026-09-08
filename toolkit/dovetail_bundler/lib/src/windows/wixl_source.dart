import 'package:dovetail_bundler/src/spec/install_mode.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:dovetail_bundler/src/windows/msi_component_tree.dart';
import 'package:dovetail_bundler/src/windows/msi_spec.dart';
import 'package:dovetail_bundler/src/windows/wix_text.dart';

abstract final class WixlSource {
  static const String schema = 'http://schemas.microsoft.com/wix/2006/wi';

  static const String installDirectoryId = 'INSTALLFOLDER';

  static String rootFolderFor(InstallMode mode, TargetArch arch) =>
      switch (mode) {
        InstallMode.perMachine =>
          arch == TargetArch.x86_64
              ? 'ProgramFiles64Folder'
              : 'ProgramFilesFolder',
        InstallMode.currentUser => 'LocalAppDataFolder',
      };

  static String render(MsiSpec spec, MsiComponentTree tree) => <String>[
    '<?xml version="1.0" encoding="utf-8"?>',
    '<Wix xmlns="$schema">',
    ..._product(spec, tree),
    '</Wix>',
    '',
  ].join('\n');

  static List<String> _product(MsiSpec spec, MsiComponentTree tree) {
    final String name = WixText.attribute(spec.bundle.productName);
    final String maker = WixText.attribute(spec.bundle.manufacturer);

    return <String>[
      '  <Product',
      '    Id="*"',
      '    Name="$name"',
      '    UpgradeCode="${spec.normalizedUpgradeCode}"',
      '    Language="1033"',
      '    Codepage="1252"',
      '    Version="${spec.productVersion}"',
      '    Manufacturer="$maker">',
      '',
      '    <Package',
      '      InstallerVersion="200"',
      '      Compressed="yes"',
      '      InstallScope="${_scopeFor(spec.bundle.installMode)}"',
      '      Manufacturer="$maker"',
      '      Description="$name ${spec.productVersion}" />',
      '',
      '    <Media Id="1" Cabinet="app.cab" EmbedCab="yes" />',
      '',
      ..._directories(spec, tree),
      '',
      ..._feature(spec, tree),
      '  </Product>',
    ];
  }

  static String _scopeFor(InstallMode mode) =>
      mode == InstallMode.perMachine ? 'perMachine' : 'perUser';

  static List<String> _directories(MsiSpec spec, MsiComponentTree tree) {
    final String root = rootFolderFor(spec.bundle.installMode, spec.arch);

    return <String>[
      '    <Directory Id="TARGETDIR" Name="SourceDir">',
      '      <Directory Id="$root">',
      '        <Directory Id="$installDirectoryId" '
          'Name="${WixText.attribute(spec.bundle.productName)}">',
      ..._componentsIn(spec, tree, installDirectoryId, 5),
      ..._childrenOf(spec, tree, null, 5),
      '        </Directory>',
      '      </Directory>',
      '    </Directory>',
    ];
  }

  static List<String> _childrenOf(
    MsiSpec spec,
    MsiComponentTree tree,
    String? relativePath,
    int depth,
  ) {
    final String pad = '  ' * depth;
    final List<String> lines = <String>[];

    for (final MsiDirectory directory in tree.childrenOf(relativePath)) {
      lines
        ..add(
          '$pad<Directory Id="${directory.id}" '
          'Name="${WixText.attribute(directory.name)}">',
        )
        ..addAll(_componentsIn(spec, tree, directory.id, depth + 1))
        ..addAll(_childrenOf(spec, tree, directory.relativePath, depth + 1))
        ..add('$pad</Directory>');
    }
    return lines;
  }

  static List<String> _componentsIn(
    MsiSpec spec,
    MsiComponentTree tree,
    String directoryId,
    int depth,
  ) {
    final String pad = '  ' * depth;
    final List<String> lines = <String>[];

    for (final MsiComponent component in tree.componentsIn(directoryId)) {
      lines
        ..add(
          '$pad<Component Id="${component.id}" Guid="${component.guid}"'
          '${spec.arch == TargetArch.x86_64 ? ' Win64="yes"' : ''}>',
        )
        ..add(
          '$pad  <File Id="${component.fileId}" '
          'Name="${WixText.attribute(component.fileName)}" '
          'Source="${WixText.attribute(component.source)}" KeyPath="yes" />',
        )
        ..add('$pad</Component>');
    }
    return lines;
  }

  static List<String> _feature(MsiSpec spec, MsiComponentTree tree) => <String>[
    '    <Feature Id="Main" '
        'Title="${WixText.attribute(spec.bundle.productName)}" Level="1">',
    for (final MsiComponent component in tree.components)
      '      <ComponentRef Id="${component.id}" />',
    '    </Feature>',
  ];
}
