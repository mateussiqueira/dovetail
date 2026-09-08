import 'package:dovetail_bundler/src/bundle_failure.dart';

enum PolkitAuthorization {
  no('no'),
  yes('yes'),
  authSelf('auth_self'),
  authSelfKeep('auth_self_keep'),
  authAdmin('auth_admin'),
  authAdminKeep('auth_admin_keep');

  const PolkitAuthorization(this.wireName);

  final String wireName;
}

final class PolkitAction {
  const PolkitAction({
    required this.id,
    required this.description,
    required this.message,
    this.iconName,
    this.allowAny = PolkitAuthorization.authAdmin,
    this.allowInactive = PolkitAuthorization.authAdmin,
    this.allowActive = PolkitAuthorization.authAdmin,
  });

  final String id;
  final String description;
  final String message;
  final String? iconName;
  final PolkitAuthorization allowAny;
  final PolkitAuthorization allowInactive;
  final PolkitAuthorization allowActive;
}

final class PolkitPolicy {
  PolkitPolicy({
    required this.namespace,
    required this.vendor,
    required this.actions,
    this.vendorUrl,
  }) {
    if (!namespace.contains('.')) {
      throw BundleFailure(
        'the polkit namespace "$namespace" is not a reverse-domain name.',
        remedy: 'Write it as com.example.app.',
      );
    }
    if (actions.isEmpty) {
      throw const BundleFailure(
        'the policy declares no action.',
        remedy:
            'A policy file with no action installs nothing polkit can be '
            'asked about.',
      );
    }

    final List<String> foreign = actions
        .map((PolkitAction action) => action.id)
        .where((String id) => !id.startsWith('$namespace.'))
        .toList(growable: false);
    if (foreign.isNotEmpty) {
      throw BundleFailure(
        'the action${foreign.length > 1 ? 's' : ''} ${foreign.join(', ')} '
        'do${foreign.length > 1 ? '' : 'es'} not live under "$namespace".',
        remedy:
            'polkit reads the file named after the namespace and ignores an '
            'action declared outside it. The authorisation check would then '
            'fail on an action nothing registered.',
      );
    }

    final Set<String> seen = <String>{};
    for (final PolkitAction action in actions) {
      if (!seen.add(action.id)) {
        throw BundleFailure(
          'the action "${action.id}" is declared twice.',
          remedy: 'polkit keeps one of the two, and which one is not defined.',
        );
      }
    }
  }

  final String namespace;
  final String vendor;
  final String? vendorUrl;
  final List<PolkitAction> actions;

  static const String installedDirectory = '/usr/share/polkit-1/actions';

  String get fileName => '$namespace.policy';

  String get installedPath => '$installedDirectory/$fileName';

  String render() {
    final StringBuffer out = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<!DOCTYPE policyconfig PUBLIC '
        '"-//freedesktop//DTD polkit Policy Configuration 1.0//EN"',
      )
      ..writeln(
        '"http://www.freedesktop.org/software/polkit/policyconfig-1.dtd">',
      )
      ..writeln('<policyconfig>')
      ..writeln('  <vendor>${_escape(vendor)}</vendor>');
    if (vendorUrl != null && vendorUrl!.trim().isNotEmpty) {
      out.writeln('  <vendor_url>${_escape(vendorUrl!)}</vendor_url>');
    }

    for (final PolkitAction action in actions) {
      out
        ..writeln()
        ..writeln('  <action id="${_escape(action.id)}">')
        ..writeln(
          '    <description>${_escape(action.description)}</description>',
        )
        ..writeln('    <message>${_escape(action.message)}</message>');
      if (action.iconName != null && action.iconName!.trim().isNotEmpty) {
        out.writeln('    <icon_name>${_escape(action.iconName!)}</icon_name>');
      }
      out
        ..writeln('    <defaults>')
        ..writeln('      <allow_any>${action.allowAny.wireName}</allow_any>')
        ..writeln(
          '      <allow_inactive>${action.allowInactive.wireName}'
          '</allow_inactive>',
        )
        ..writeln(
          '      <allow_active>${action.allowActive.wireName}</allow_active>',
        )
        ..writeln('    </defaults>')
        ..writeln('  </action>');
    }

    out.writeln('</policyconfig>');
    return out.toString();
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
