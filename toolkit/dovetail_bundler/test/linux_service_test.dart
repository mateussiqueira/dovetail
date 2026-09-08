import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

SystemdUnit unitWith({
  String fileName = 'client-helper.service',
  String execStart = '/usr/lib/client/privileged-helper',
  Set<String> bounding = const <String>{'CAP_NET_ADMIN'},
  Set<String> ambient = const <String>{'CAP_NET_ADMIN'},
  List<String> wantedBy = const <String>['multi-user.target'],
  SystemdDirectory? runtime,
  SystemdDirectory? logs,
}) => SystemdUnit(
  fileName: fileName,
  description: 'Example privileged helper',
  execStart: execStart,
  capabilityBoundingSet: bounding,
  ambientCapabilities: ambient,
  wantedBy: wantedBy,
  runtimeDirectory: runtime,
  logsDirectory: logs,
);

PolkitPolicy policyWith({
  String namespace = 'io.example.client',
  List<String> actionIds = const <String>['io.example.client.manage'],
}) => PolkitPolicy(
  namespace: namespace,
  vendor: 'Example Ltda',
  actions: actionIds
      .map(
        (String id) => PolkitAction(
          id: id,
          description: 'Manage the connection',
          message: 'Authentication is required.',
        ),
      )
      .toList(growable: false),
);

void main() {
  late Directory root;
  late String app;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_linux_service');
    app = p.join(root.path, 'bundle');
    Directory(app).createSync(recursive: true);
    File(p.join(app, 'client')).writeAsStringSync('binary');
    File(p.join(app, 'privileged-helper')).writeAsStringSync('binary');
  });

  tearDown(() => root.deleteSync(recursive: true));

  BundleSpec specFor() => BundleSpec(
    productName: 'Example Client',
    manufacturer: 'Example Ltda',
    identifier: 'io.example.client',
    version: AppVersion.parse('2.1.0'),
    mainBinaryName: 'client',
    appDirectory: app,
    outputDirectory: p.join(root.path, 'out'),
  );

  group('SystemdUnit', () {
    test('should write the sections systemd needs to enable it', () {
      final String rendered = unitWith().render();
      expect(rendered, contains('[Unit]'));
      expect(rendered, contains('[Service]'));
      expect(rendered, contains('[Install]'));
      expect(rendered, contains('WantedBy=multi-user.target'));
    });

    test('should install where a package unit belongs', () {
      expect(
        unitWith().installedPath,
        '/usr/lib/systemd/system/client-helper.service',
      );
    });

    test('should refuse a name systemd would not read as a service', () {
      expect(
        () => unitWith(fileName: 'client-helper'),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should refuse an ExecStart that is not absolute', () {
      expect(
        () => unitWith(execStart: 'privileged-helper'),
        throwsA(isA<BundleFailure>()),
      );
      expect(() => unitWith(execStart: '  '), throwsA(isA<BundleFailure>()));
    });

    test('should refuse a unit with no install target', () {
      expect(
        () => unitWith(wantedBy: const <String>[]),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('never starts'),
          ),
        ),
      );
    });

    test('an ambient capability outside the bounding set should be fatal', () {
      expect(
        () => unitWith(
          bounding: const <String>{'CAP_NET_ADMIN'},
          ambient: const <String>{'CAP_NET_ADMIN', 'CAP_NET_RAW'},
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('silently'),
          ),
        ),
        reason:
            'systemd drops it without a word, so the service starts and the '
            'privileged call fails only when a user needs it',
      );
    });

    test('an empty ambient set should not trip the bounding-set check', () {
      expect(
        () => unitWith(
          bounding: const <String>{'CAP_NET_ADMIN'},
          ambient: const <String>{},
        ),
        returnsNormally,
      );
    });

    test('should refuse an absolute runtime directory', () {
      expect(
        () => unitWith(
          runtime: const SystemdDirectory(name: '/run/example', mode: '0700'),
        ),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('a directory should carry its mode, not systemd 0755 default', () {
      final String rendered = unitWith(
        runtime: const SystemdDirectory(name: 'example', mode: '0700'),
        logs: const SystemdDirectory(name: 'example', mode: '0750'),
      ).render();
      expect(rendered, contains('RuntimeDirectory=example'));
      expect(rendered, contains('RuntimeDirectoryMode=0700'));
      expect(rendered, contains('LogsDirectoryMode=0750'));
    });

    test('the hardening it always writes should include NoNewPrivileges', () {
      final String rendered = unitWith().render();
      for (final String directive in <String>[
        'NoNewPrivileges=yes',
        'ProtectHome=yes',
        'RestrictSUIDSGID=yes',
        'MemoryDenyWriteExecute=yes',
        'SystemCallArchitectures=native',
      ]) {
        expect(rendered, contains(directive));
      }
    });

    test('the same unit should render byte for byte the same', () {
      expect(unitWith().render(), unitWith().render());
    });

    test('a capability set should render in a stable order', () {
      expect(
        SystemdUnit(
          fileName: 'a.service',
          description: 'a',
          execStart: '/a',
          capabilityBoundingSet: const <String>{'CAP_NET_RAW', 'CAP_NET_ADMIN'},
        ).render(),
        contains('CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW'),
      );
    });

    test('the toolkit should carry no default capability of its own', () {
      expect(
        SystemdUnit(
          fileName: 'a.service',
          description: 'a',
          execStart: '/a',
        ).render(),
        isNot(contains('CapabilityBoundingSet')),
        reason:
            'which privilege a service needs is the application deciding, not '
            'this package guessing',
      );
    });
  });

  group('PolkitPolicy', () {
    test(
      'should be named after its namespace, which is how polkit reads it',
      () {
        expect(policyWith().fileName, 'io.example.client.policy');
        expect(
          policyWith().installedPath,
          '/usr/share/polkit-1/actions/io.example.client.policy',
        );
      },
    );

    test('should refuse an action declared outside its namespace', () {
      expect(
        () => policyWith(
          namespace: 'io.example.client',
          actionIds: const <String>['io.other.app.manage'],
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('ignores'),
          ),
        ),
      );
    });

    test('should refuse a duplicate action id', () {
      expect(
        () => policyWith(
          actionIds: const <String>[
            'io.example.client.manage',
            'io.example.client.manage',
          ],
        ),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should refuse a policy with no action', () {
      expect(
        () => PolkitPolicy(
          namespace: 'io.example.client',
          vendor: 'Example',
          actions: const <PolkitAction>[],
        ),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should refuse a namespace that is not reverse-domain', () {
      expect(
        () => policyWith(
          namespace: 'client',
          actionIds: const <String>['client.manage'],
        ),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should write the doctype polkit validates against', () {
      final String rendered = policyWith().render();
      expect(rendered, contains('<!DOCTYPE policyconfig PUBLIC'));
      expect(rendered, contains('policyconfig-1.dtd'));
    });

    test('should escape a vendor name that carries markup', () {
      expect(
        PolkitPolicy(
          namespace: 'io.example.client',
          vendor: 'Example & <Co>',
          actions: <PolkitAction>[
            const PolkitAction(
              id: 'io.example.client.manage',
              description: 'x',
              message: 'y',
            ),
          ],
        ).render(),
        contains('<vendor>Example &amp; &lt;Co&gt;</vendor>'),
      );
    });

    test('the default should ask for admin, not grant silently', () {
      final String rendered = policyWith().render();
      expect(rendered, contains('<allow_any>auth_admin</allow_any>'));
      expect(rendered, contains('<allow_active>auth_admin</allow_active>'));
    });
  });

  group('ServiceScripts', () {
    test('debian should read the first argument as a verb', () {
      final ServiceScripts scripts = ServiceScripts(
        unitFileName: 'client-helper.service',
      );
      expect(scripts.debianPostinst, contains(r'[ "$1" = "configure" ]'));
      expect(scripts.debianPrerm, contains(r'[ "$1" = remove ]'));
      expect(scripts.debianPostrm, contains(r'[ "$1" = "purge" ]'));
    });

    test('rpm should use the macros rather than systemctl directly', () {
      final ServiceScripts scripts = ServiceScripts(
        unitFileName: 'client-helper.service',
      );
      expect(scripts.rpmPost, contains('%systemd_post client-helper.service'));
      expect(scripts.rpmPreun, contains('%systemd_preun'));
      expect(scripts.rpmPostun, contains('%systemd_postun_with_restart'));
      expect(
        scripts.rpmPost,
        isNot(contains('systemctl')),
        reason:
            'in rpm \$1 is a count, not a verb, and the macros are what get '
            'that right across install, upgrade and erase',
      );
    });

    test('debian should restart on upgrade and start on first install', () {
      expect(
        ServiceScripts(unitFileName: 'a.service').debianPostinst,
        contains(r'if [ -n "$2" ]'),
      );
    });

    test('purge should remove only what the unit left behind', () {
      final ServiceScripts scripts = ServiceScripts(
        unitFileName: 'a.service',
        purgePaths: const <String>['/var/log/example'],
      );
      expect(scripts.debianPostrm, contains("_purge_paths='/var/log/example'"));
      expect(scripts.debianPostrm, contains('rm -rf'));
    });

    test('no purge path should mean no rm -rf at all', () {
      expect(
        ServiceScripts(unitFileName: 'a.service').debianPostrm,
        isNot(contains('rm -rf')),
      );
    });

    test('should refuse a relative purge path', () {
      expect(
        () => ServiceScripts(
          unitFileName: 'a.service',
          purgePaths: const <String>['var/log/example'],
        ),
        throwsA(isA<BundleFailure>()),
      );
    });

    test('should refuse a purge path with a space', () {
      expect(
        () => ServiceScripts(
          unitFileName: 'a.service',
          purgePaths: const <String>['/var/log/my example'],
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('two wrong paths'),
          ),
        ),
      );
    });

    test('should refuse a purge path close to the root', () {
      for (final String dangerous in <String>['/', '/var', '/usr']) {
        expect(
          () => ServiceScripts(
            unitFileName: 'a.service',
            purgePaths: <String>[dangerous],
          ),
          throwsA(isA<BundleFailure>()),
          reason: dangerous,
        );
      }
    });

    test('every script should be a shell script that exits zero', () {
      final ServiceScripts scripts = ServiceScripts(unitFileName: 'a.service');
      for (final String script in <String>[
        scripts.debianPostinst,
        scripts.debianPrerm,
        scripts.debianPostrm,
      ]) {
        expect(script, startsWith('#!/bin/sh\nset -e\n'));
        expect(script.trimRight(), endsWith('exit 0'));
      }
    });
  });

  group('DesktopEntry', () {
    test('should be named reverse-DNS, which is what a portal matches', () {
      expect(
        DesktopEntry.forSpec(specFor()).fileName,
        'io.example.client.desktop',
      );
    });

    test('the icon and the window class should be the app id', () {
      final String rendered = DesktopEntry.forSpec(specFor()).render();
      expect(rendered, contains('Icon=io.example.client'));
      expect(rendered, contains('StartupWMClass=io.example.client'));
    });

    test('should refuse a short id', () {
      expect(
        () => DesktopEntry(appId: 'client', name: 'Client', exec: '/usr/bin/c'),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('portal'),
          ),
        ),
      );
    });

    test('should refuse a relative Exec', () {
      expect(
        () => DesktopEntry(
          appId: 'io.example.client',
          name: 'Client',
          exec: 'client',
        ),
        throwsA(isA<BundleFailure>()),
      );
    });
  });

  group('the deb it produces', () {
    Future<Archive> archiveIn(String deb, String member) async {
      final ProcessResult extracted = Process.runSync('ar', <String>[
        'p',
        deb,
        member,
      ], stdoutEncoding: null);
      expect(extracted.exitCode, 0, reason: extracted.stderr.toString());
      return TarDecoder().decodeBytes(
        const GZipDecoder().decodeBytes(extracted.stdout as List<int>),
      );
    }

    test(
      'should install the unit, the policy and the reverse-DNS desktop',
      () async {
        final SystemdUnit unit = unitWith();
        final String deb = await DebBundler(
          unit: unit,
          policy: policyWith(),
          scripts: ServiceScripts(unitFileName: unit.fileName),
        ).bundle(specFor());

        final Archive data = await archiveIn(deb, 'data.tar.gz');
        final Set<String> names = data.files
            .map((ArchiveFile file) => file.name)
            .toSet();
        expect(
          names,
          containsAll(<String>[
            'usr/lib/systemd/system/client-helper.service',
            'usr/share/polkit-1/actions/io.example.client.policy',
            'usr/share/applications/io.example.client.desktop',
          ]),
        );
      },
    );

    test('the maintainer scripts should be executable', () async {
      final SystemdUnit unit = unitWith();
      final String deb = await DebBundler(
        unit: unit,
        policy: policyWith(),
        scripts: ServiceScripts(unitFileName: unit.fileName),
      ).bundle(specFor());

      final Archive control = await archiveIn(deb, 'control.tar.gz');
      for (final String name in <String>['postinst', 'prerm', 'postrm']) {
        final ArchiveFile script = control.files.firstWhere(
          (ArchiveFile file) => file.name == name,
        );
        expect(
          script.mode & 0x49,
          0x49,
          reason:
              '$name is not executable, and dpkg skips a maintainer script it '
              'cannot run without failing the install',
        );
      }
    });

    test(
      'a package with no service should carry no maintainer script',
      () async {
        final String deb = await const DebBundler().bundle(specFor());
        final Archive control = await archiveIn(deb, 'control.tar.gz');
        expect(control.files.map((ArchiveFile file) => file.name), <String>[
          'control',
        ]);
      },
    );

    test('a unit with no scripts should be refused', () async {
      await expectLater(
        DebBundler(unit: unitWith()).bundle(specFor()),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('never starts'),
          ),
        ),
      );
    });

    test('scripts naming another unit should be refused', () async {
      await expectLater(
        DebBundler(
          unit: unitWith(fileName: 'one.service'),
          scripts: ServiceScripts(unitFileName: 'two.service'),
        ).bundle(specFor()),
        throwsA(isA<BundleFailure>()),
      );
    });
  });

  group('the rpm spec it produces', () {
    String specText({SystemdUnit? unit, PolkitPolicy? policy}) => RpmBundler(
      runner: const SystemProcessRunner(),
      unit: unit,
      policy: policy,
      scripts: unit == null
          ? null
          : ServiceScripts(unitFileName: unit.fileName),
    ).specFileFor(specFor());

    test('a unit should bring the macros it expands with', () {
      expect(
        specText(unit: unitWith()),
        contains('BuildRequires: systemd-rpm-macros'),
        reason:
            'measured on this machine: without them rpmbuild succeeds and '
            'writes the literal %systemd_post as the scriptlet, so the '
            'service is never enabled and the rpm looks fine',
      );
      expect(specText(unit: unitWith()), contains(r'%{?systemd_requires}'));
    });

    test('a policy should require polkit at runtime', () {
      expect(
        specText(unit: unitWith(), policy: policyWith()),
        contains('Requires: polkit'),
      );
    });

    test('every installed file should be declared in %files', () {
      final String text = specText(unit: unitWith(), policy: policyWith());
      for (final String path in <String>[
        '/usr/lib/client',
        '/usr/share/applications/io.example.client.desktop',
        '/usr/lib/systemd/system/client-helper.service',
        '/usr/share/polkit-1/actions/io.example.client.policy',
      ]) {
        expect(text, contains(path));
      }
    });

    test('a spec with no unit should carry no scriptlet and no macros', () {
      final String text = specText();
      expect(text, isNot(contains('%post')));
      expect(text, isNot(contains('systemd-rpm-macros')));
    });
  });
}
