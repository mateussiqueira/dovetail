// The esteira, for a repository whose only green was one machine.
//
// A CI workflow now exists (.github/workflows/ci.yml) and Actions is enabled
// on this account, but no hosted run has returned green yet — and this laptop
// remains the only machine that has ever rerun these tests. That makes the
// green here the only green there is, and green here has been compatible with
// "not proven" in three different ways: a suite that moved the process cwd
// and made others skip in silence, a `return` inside main() that deleted
// seventeen tests without registering them, and guards that could not tell
// "the tool is missing" from "the tool is there and failed".
//
// So this does not just run the tests. It records what each suite DECLARED
// and what it SKIPPED, and compares that against a versioned baseline. A test
// that disappears is the patology this exists to catch; a count that drops is
// a failure, a count that rises is news.
//
// No package dependencies on purpose: the repository root has no pubspec, and
// the one command that has to work when everything else is broken should not
// need `pub get` first.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const String _baselineFile = 'tool/skip_baseline.json';
const String _runFile = 'dist/verify-run.json';

/// Every package, and the runner that owns it.
///
/// `product/` is here as well as `toolkit/`. The toolkit is the part meant to
/// be reused, but the app is the only thing that proves the toolkit joins up,
/// and a gate that stops at the library lets the joint rot between commits.
const List<(String, String)> _packages = <(String, String)>[
  ('toolkit/dovetail_bundler', 'dart'),
  ('toolkit/dovetail_signer', 'dart'),
  ('toolkit/dovetail_updater', 'dart'),
  ('toolkit/dovetail_cli', 'dart'),
  ('toolkit/dovetail_form_validation', 'dart'),
  ('toolkit/dovetail_process_runner', 'dart'),
  ('toolkit/dovetail_platform_channel', 'flutter'),
  ('toolkit/dovetail_shortcut_channel', 'flutter'),
  ('toolkit/dovetail', 'flutter'),
  ('toolkit/dovetail_rust_core', 'flutter'),
  ('product/desktop_core_bridge', 'flutter'),
  ('product/vpn_desktop', 'flutter'),
];

/// O alvo que nao rodou, e o motivo, com o mesmo cabecalho que ele teria.
///
/// Devolve 0 porque nao rodar nao e falhar — mas imprime a linha, que e a
/// diferenca entre "pulou e disse" e "saiu verde". Um resumo em que `frb ok`
/// aparece sem o codegen ter sido consultado e um resumo que mente.
int _skippedBridge(String target) {
  stdout.writeln('── $target ──');
  stdout.writeln(
    '  skipped  pede product/desktop_core_bridge, que resolve as crates no '
    'irmao privado (--only)',
  );
  return 0;
}

/// Os pacotes que este alvo deve tocar.
///
/// `--only` nao e conveniencia: e a unica forma de este repositorio ser
/// verificavel por quem nao tem os dois irmaos privados. `product/vpn_desktop`
/// resolve o design system em `../../../example-design-system` e
/// `product/desktop_core_bridge` puxa as crates de `../../../example-rust`,
/// entao qualquer alvo que os inclua morre no `pub get` de um clone limpo.
///
/// Antes disto, `fast` — o alvo que o `pre-commit` roda — ignorava `--only` e
/// analisava os doze, e `cross --only toolkit` chamava `_pluginCoverage` de
/// qualquer jeito: os dois comandos que o CI ja invocava achando que eram
/// toolkit-only nao eram, e o primeiro `git commit` de um segundo engenheiro
/// falhava.
List<(String, String)> _selected(String? only) => <(String, String)>[
  for (final (String, String) each in _packages)
    if (only == null || each.$1.contains(only)) each,
];

/// Tools a skip in the baseline depends on. If one of these disappears, a
/// test that used to run turns into a skip — which the baseline catches on
/// its own. They are listed so `doctor` can say WHY before the suite does.
/// As ferramentas que os testes de fato invocam, lidas da arvore.
///
/// Era uma lista escrita a mao, e ela tinha derivado dos dois lados: nomeava
/// `rpmbuild`, `wixl` e `ditto`, que teste nenhum chama, e omitia `codesign`,
/// `rustup`, `rustc`, `python3`, `shasum`, `sips`, `file`, `msiinfo`,
/// `msiextract`, `hdiutil`, `rpm` e `ar`, que sao chamados. Um `doctor` que
/// diz "absent rpmbuild" para uma maquina onde nenhum skip depende disso, e
/// cala sobre o `codesign` que falta, informa ao contrario.
///
/// Derivada em vez de escrita: a unica forma de nao envelhecer de novo. O que
/// se procura e a forma literal `Process.run…('<nome>'` — que e como todo
/// shell-out nos testes deste repositorio comeca.
List<String> _toolsBehindSkips() {
  // Sempre presentes num host que ja roda o portao: procurar por elas so
  // produziria ruido. `which` e a propria sonda.
  const Set<String> ubiquitous = <String>{
    'ar',
    'chmod',
    'cp',
    'dart',
    'flutter',
    'tar',
    'which',
  };
  final RegExp call = RegExp(r"Process\.(?:run|runSync|start)\(\s*'([\w.-]+)'");
  final Set<String> found = <String>{};
  for (final (String package, _) in _packages) {
    final Directory tests = Directory('$repoRoot/$package/test');
    if (!tests.existsSync()) {
      continue;
    }
    for (final FileSystemEntity entity in tests.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      for (final RegExpMatch match in call.allMatches(
        entity.readAsStringSync(),
      )) {
        final String tool = match.group(1)!;
        if (!ubiquitous.contains(tool)) {
          found.add(tool);
        }
      }
    }
  }
  return found.toList()..sort();
}

/// Without these nothing runs at all.
const List<String> _required = <String>['dart', 'flutter', 'cargo', 'git'];

late final String repoRoot = _findRepoRoot();

Future<void> main(List<String> arguments) async {
  // exitCode, not `return`. Dart ignores what main gives back, so a verifier
  // written as `Future<int> main` exits 0 no matter what it printed — and a
  // hook hanging off it would wave every red through while looking diligent.
  exitCode = await _run(arguments);
}

const String _usage = '''
usage: dart tool/verify.dart [target] [--only <substring>]

targets   doctor    the host: tools present, hooks installed
          fast      analyze + format, what a commit can afford   (pre-commit)
          test      every suite, in lanes; writes dist/verify-run.json
          baseline  compare the last run against tool/skip_baseline.json
          bless     make the last run the baseline (refuses partial or red)
          cross     typecheck the Windows/Linux natives from this host
          rust      cargo test + clippy on the crates
          frb       the bridge codegen is current
          ffi       a Dart call reaches Rust and comes back (macOS)
          release   the whole macOS pipeline against a local host, signed and
                    verified end to end (macOS, needs the product built)
          readme    the README table agrees with the baseline
          install   point core.hooksPath at tool/githooks
          all       every target above, exit code decided at the end

--only    narrows fast, test, cross, rust and all to packages whose path
          contains the substring. It is how you iterate on one package:
            dart tool/verify.dart test --only dovetail_form_validation     ~1s
          against the whole thing at ~46s. A --only run is visibly partial —
          the readme target lists what did not run, and bless refuses it.

DOVETAIL_LANES=<n>       dart packages tested at once (default 3)
DOVETAIL_SUITE_JOBS=<n>  suites per package at once   (default 4)
''';

Future<int> _run(List<String> arguments) async {
  // `--only x` sem alvo é `all --only x`: a flag era invisível — aparecia uma
  // vez, em tool/githooks/pre-push, que é quando você já travou — e dada como
  // primeiro argumento virava `unknown target "--only"`.
  final String target = arguments.isEmpty || arguments.first.startsWith('--')
      ? 'all'
      : arguments.first;
  switch (target) {
    case 'help':
    case '-h':
    case '--help':
      stdout.write(_usage);
      return 0;
    case 'doctor':
      return _doctor();
    case 'test':
      return (await _test(only: _only(arguments))).failed ? 1 : 0;
    case 'baseline':
      return _compare(_readRun());
    case 'bless':
      return _bless(arguments.skip(1).toList());
    case 'fast':
      return await _fast(only: _only(arguments));
    case 'cross':
      return _cross(only: _only(arguments));
    case 'rust':
      return _rustTests(only: _only(arguments));
    case 'frb':
      return _bridgeIsGenerated();
    case 'ffi':
      return _ffiCrosses();
    case 'release':
      return _releaseProof(only: _only(arguments));
    case 'readme':
      return _readme();
    case 'install':
      return _install();
    case 'all':
      return _all(only: _only(arguments));
    default:
      stderr.writeln('unknown target "$target".');
      stderr.write(_usage);
      return 64;
  }
}

// ---------------------------------------------------------------- all

Future<int> _all({String? only}) async {
  // `frb` e `ffi` leem `product/desktop_core_bridge` — o codegen num, o app
  // de exemplo no outro —, e esse pacote puxa as crates do irmao privado.
  // Sob `--only toolkit` eles nao tem o que ler, e a escolha aqui e dizer
  // isso em vez de devolver 0: `_ffiCrosses` ja tem o habito de imprimir
  // "skipped" e retornar verde fora do macOS, e verde onde nao se provou nada
  // e exatamente o que este arquivo existe para impedir.
  final bool bridge = _selected(
    only,
  ).any(((String, String) each) => each.$1 == 'product/desktop_core_bridge');

  // Everything runs and everything reports, then the exit code is decided at
  // the end. Stopping at the first failure is right for a pipeline that runs
  // on every push; it is wrong for the only check on the machine, where a
  // missing tool would hide whether the code itself is fine.
  final int doctorCode = _doctor();
  final int fastCode = await _fast(only: only);
  final int crossCode = _cross(only: only);
  final int rustCode = _rustTests(only: only);
  final int frbCode = bridge ? _bridgeIsGenerated() : _skippedBridge('frb');
  final int ffiCode = bridge ? _ffiCrosses() : _skippedBridge('ffi');
  final int releaseCode = _releaseProof(only: only);
  final int readmeCode = _readme();
  final _Run run = await _test(only: only);
  // Null, not 1. A failed run declares fewer tests than it should — that is
  // what failing means — so comparing it against the baseline reports drift
  // that is really just the failure, twice. But calling a step that never ran
  // "failed" is how a summary stops being read: the line has to say which of
  // the two happened.
  final int? baselineCode = run.failed ? null : _compare(run);

  final bool ok =
      doctorCode == 0 &&
      fastCode == 0 &&
      crossCode == 0 &&
      rustCode == 0 &&
      frbCode == 0 &&
      ffiCode == 0 &&
      releaseCode == 0 &&
      readmeCode == 0 &&
      !run.failed &&
      baselineCode == 0;
  stdout.writeln('');
  stdout.writeln(ok ? 'verify: ok' : 'verify: FAILED');
  if (!ok) {
    stdout.writeln(
      '  doctor ${doctorCode == 0 ? 'ok' : 'failed'} · '
      'fast ${fastCode == 0 ? 'ok' : 'failed'} · '
      'cross ${crossCode == 0 ? 'ok' : 'failed'} · '
      'rust ${rustCode == 0 ? 'ok' : 'failed'} · '
      'frb ${frbCode == 0 ? 'ok' : 'failed'} · '
      'ffi ${ffiCode == 0 ? 'ok' : 'failed'} · '
      'release ${releaseCode == 0 ? 'ok' : 'failed'} · '
      'readme ${readmeCode == 0 ? 'ok' : 'failed'} · '
      'test ${run.failed ? 'failed' : 'ok'} · '
      'baseline ${switch (baselineCode) {
        null => 'not run, because test failed',
        0 => 'ok',
        _ => 'failed',
      }}',
    );
  }
  return ok ? 0 : 1;
}

// ---------------------------------------------------------------- doctor

int _doctor() {
  stdout.writeln('── doctor ──');
  int missing = 0;

  for (final String tool in _required) {
    final String? at = _which(tool);
    if (at == null) {
      stdout.writeln('  MISSING  $tool  (nothing runs without it)');
      missing++;
    }
  }
  // Nao esta em `_required` porque o portao inteiro roda sem ele — mas mexer
  // na ponte nao. Quem clona e edita `rust/src/api/` sem esta ferramenta
  // escreve um metodo que o Dart nunca ve, e nada avisa.
  if (_which('flutter_rust_bridge_codegen') == null) {
    stdout.writeln(
      '  absent   flutter_rust_bridge_codegen — sem ele o Dart da ponte nao '
      'se regenera. cargo install flutter_rust_bridge_codegen '
      '--version $_frbPinned',
    );
  }

  final List<String> absent = <String>[
    for (final String tool in _toolsBehindSkips())
      if (_which(tool) == null) tool,
  ];
  if (absent.isNotEmpty) {
    stdout.writeln(
      '  absent   ${absent.join(', ')}  — tests that need them will skip, and '
      'the baseline will say so by name',
    );
  }

  // Detected, never written. core.hooksPath is shared by every worktree, so a
  // command that quietly sets it changes how another session commits.
  final String configured = _git(<String>['config', '--get', 'core.hooksPath']);
  final String wanted = '$repoRoot/tool/githooks';
  if (configured.trim() != wanted) {
    stdout.writeln(
      '  hooks    not installed. Run: dart tool/verify.dart install',
    );
  }

  stdout.writeln(missing == 0 ? '  ok' : '  $missing required tool missing');
  return missing == 0 ? 0 : 1;
}

int _install() {
  final String wanted = '$repoRoot/tool/githooks';
  final String configured = _git(<String>[
    'config',
    '--get',
    'core.hooksPath',
  ]).trim();

  if (configured == wanted) {
    stdout.writeln('hooks already point at $wanted');
    return 0;
  }
  if (configured.isNotEmpty) {
    stderr.writeln(
      'core.hooksPath is already "$configured", and it is shared by every '
      'worktree of this repository. Change it by hand if you mean to:\n'
      '  git config core.hooksPath $wanted',
    );
    return 1;
  }
  // Absolute, not relative: worktrees share .git/config, and a relative path
  // resolves against each worktree's own root, so the hooks silently vanish
  // in every worktree but the main one.
  _git(<String>['config', 'core.hooksPath', wanted]);
  stdout.writeln('hooks installed: core.hooksPath = $wanted');
  return 0;
}

/// The lane a commit can afford. `all` takes about a hundred seconds and
/// drives makensis, wixl, rpmbuild, rustc and minisign; hung on every commit
/// that becomes a hook somebody deletes, and then the machine checks nothing.
Future<int> _fast({String? only}) async {
  stdout.writeln('── fast ──');
  int failed = _resolveUnresolved(only: only);

  // Os doze `analyze` em paralelo, e nao num for loop de `runSync`.
  //
  // Medido nesta maquina, arvore quente: `flutter analyze` custa 2,0-2,8s e
  // sao seis pacotes flutter; `dart analyze` custa 0,5-0,7s e sao seis. Em
  // sequencia isso e ~18,5s dos 21,9s que o alvo levava — e este e o alvo do
  // `pre-commit`, entao era um imposto de vinte segundos em TODO commit.
  //
  // Analyze e um processo por pacote que so le: nao ha diretorio de build
  // disputado nem cache escrito em comum, que e o que obrigou o `test` a
  // serializar os pacotes flutter. Aqui a concorrencia e de graca.
  //
  // A saida e ordenada por pacote depois, e nao na ordem em que os processos
  // terminam: um relatorio que muda de ordem entre corridas e um relatorio
  // que ninguem compara.
  // Em lanes, e nao os doze de uma vez.
  //
  // `flutter analyze` sobe um servidor de analise por pacote, e seis deles
  // simultaneos sao a mesma superassinatura que obrigou o `test` a serializar
  // os pacotes flutter — o comentario das lanes ali diz que carga e o que faz
  // flake flakear. A largura vem do host, com teto: acima de meia duzia o
  // relogio para de melhorar e so a memoria sobe.
  final List<(String, String)> wanted = _selected(only);
  final int width = math.min(6, math.max(2, Platform.numberOfProcessors - 2));
  final List<ProcessResult> analyzed = <ProcessResult>[];
  for (int from = 0; from < wanted.length; from += width) {
    analyzed.addAll(
      await Future.wait(<Future<ProcessResult>>[
        for (final (String package, String runner)
            in wanted.skip(from).take(width))
          Process.run(runner, <String>[
            'analyze',
          ], workingDirectory: '$repoRoot/$package'),
      ]),
    );
  }
  for (int i = 0; i < wanted.length; i++) {
    if (analyzed[i].exitCode != 0) {
      failed++;
      stdout.writeln('  FAILED   ${wanted[i].$1}');
      stdout.writeln(analyzed[i].stdout.toString().trimRight());
    }
  }

  failed += _format(only: only);
  failed += _rustFormat(only: only);

  stdout.writeln(failed == 0 ? '  ok' : '  $failed problem(s)');
  return failed == 0 ? 0 : 1;
}

/// Resolve o que ainda nao foi resolvido, antes de analisar.
///
/// Sem isto, `verify fast` num clone limpo reporta **124 problemas** — e
/// nenhum deles e real. O analisador sobre um pacote sem `.dart_tool` acha que
/// `ProcessOutcome` nao existe, que `expect` nao esta definida e que o
/// `analysis_options.yaml` aponta para um pacote inexistente; a causa unica
/// aparece uma vez, no meio, e as outras 123 linhas a enterram.
///
/// Isso foi medido clonando de verdade. O `_test` ja resolvia sozinho, porque
/// o hook de push roda numa worktree e ali esse e o caso comum — o `fast`
/// tinha ficado para tras, e o `fast` e o primeiro comando que alguem roda.
///
/// `--enforce-lockfile` porque os locks sao versionados: resolucao que nao
/// bate com eles e deriva, nao detalhe a absorver em silencio.
int _resolveUnresolved({String? only}) {
  final List<(String, String)> unresolved = <(String, String)>[
    for (final (String package, String runner) in _selected(only))
      if (!File(
        '$repoRoot/$package/.dart_tool/package_config.json',
      ).existsSync())
        (package, runner),
  ];
  if (unresolved.isEmpty) {
    return 0;
  }

  stdout.writeln('  resolving ${unresolved.length} package(s) first');
  int failed = 0;
  for (final (String package, String runner) in unresolved) {
    final ProcessResult resolved = Process.runSync(runner, <String>[
      'pub',
      'get',
      '--enforce-lockfile',
    ], workingDirectory: '$repoRoot/$package');
    if (resolved.exitCode != 0) {
      failed++;
      stdout.writeln('  UNRESOLVED $package');
      stdout.writeln(
        '           ${resolved.stderr.toString().trim().split('\n').first}',
      );
    }
  }
  return failed;
}

/// `dart format` sobre o que e nosso, e so sobre o que e nosso.
///
/// Duas pastas ficam de fora, e as duas por motivo, nao por comodidade. O
/// `cargokit/` e copia vendorizada de um projeto ARQUIVADO, e existe um check
/// no `cross` que compara as duas copias byte a byte: reformatar aqui as faria
/// divergir do upstream que nunca mais vai responder. E `build/` e saida de
/// build, que nao esta no git.
///
/// O que sobrou quando isto foi escrito era um arquivo so — o resto do que o
/// `dart format .` acusava era exatamente essas duas pastas, e e por isso que
/// a checagem nao existia: rodada larga demais, ela so gritava.
int _format({String? only}) {
  const List<String> ours = <String>['lib', 'bin', 'test'];

  // Uma invocacao, e nao vinte e oito.
  //
  // Era um `dart format` por (pacote x diretorio): treze pacotes vezes ate
  // tres diretorios, cada um pagando o custo de subir o formatador. Medido
  // nesta maquina, 2,25-2,60s de um alvo que roda em todo commit. O `dart
  // format` aceita a lista inteira de uma vez, e ai o custo e um.
  //
  // `tool` entra sempre, inclusive sob `--only`. Nao depende de irmao nenhum,
  // e e o diretorio que todo contribuidor toca: deixa-lo de fora do lane que
  // um clone sem os irmaos consegue rodar seria tirar do portao justamente o
  // arquivo que define o portao.
  final List<String> targets = <String>[
    for (final (String package, _) in _selected(only))
      for (final String each in ours)
        if (Directory('$repoRoot/$package/$each').existsSync())
          '$package/$each',
    if (Directory('$repoRoot/tool').existsSync()) 'tool',
  ];
  if (targets.isEmpty) {
    return 0;
  }

  final ProcessResult checked = Process.runSync('dart', <String>[
    'format',
    '--output=none',
    '--set-exit-if-changed',
    ...targets,
  ], workingDirectory: repoRoot);

  // O filtro de `cargokit/` e load-bearing, nao higiene: as duas copias
  // vendorizadas sao de um projeto ARQUIVADO, e o `cross` compara as duas byte
  // a byte. Reformatar aqui as faria divergir do upstream que nunca mais vai
  // responder — sao dezessete arquivos que aparecem como `Changed` em toda
  // corrida. E `build/` e saida de build, que nem esta no git.
  //
  // Os caminhos agora ja vem relativos a raiz, porque o processo roda nela: o
  // prefixo por pacote que existia aqui passaria a duplicar.
  final List<String> unformatted = const LineSplitter()
      .convert(checked.stdout.toString())
      .where((String line) => line.startsWith('Changed '))
      .map((String line) => line.substring(8))
      .where(
        (String path) =>
            !path.contains('/cargokit/') && !path.contains('/build/'),
      )
      .toList();

  if (unformatted.isEmpty) {
    return 0;
  }
  stdout.writeln('  UNFORMATTED');
  for (final String path in unformatted.take(10)) {
    stdout.writeln('           $path');
  }
  stdout.writeln('           Run: dart format <path>');
  return 1;
}

/// What this Mac can prove about the two systems it is not.
///
/// Not a substitute for running there — it says "compiles", never "works".
/// But `toolkit/dovetail_platform_channel/windows` is 329 lines of C++ that
/// had never been through a compiler on any host, and cargo had never been
/// asked whether the crates typecheck for the Windows and Linux triples. Both
/// answers cost seconds here, and both were simply never asked.
int _cross({String? only}) {
  stdout.writeln('── cross ──');
  int failed = 0;

  const String mingw = 'x86_64-w64-mingw32-g++';
  final String windows = '$repoRoot/toolkit/dovetail_platform_channel/windows';
  if (_which(mingw) == null) {
    stdout.writeln('  absent   $mingw — the Windows C++ stays unbuilt');
  } else {
    final Directory scratch = Directory.systemTemp.createTempSync('dovetail_x');
    try {
      for (final FileSystemEntity source in Directory(windows).listSync()) {
        if (!source.path.endsWith('.cpp')) {
          continue;
        }
        final String name = source.uri.pathSegments.last;
        final ProcessResult built = Process.runSync(mingw, <String>[
          '-c',
          '-std=c++17',
          '-I',
          'include',
          '-DDOVETAIL_BUILDING_DLL',
          name,
          '-o',
          '${scratch.path}/$name.o',
        ], workingDirectory: windows);
        if (built.exitCode != 0) {
          failed++;
          stdout.writeln('  FAILED   $name');
          stdout.writeln(
            '           ${built.stderr.toString().trim().split('\n').first}',
          );
        } else {
          stdout.writeln('  ok       $name compiles for Windows');
        }
      }

      // The Dart side looks these up by name through dart:ffi. A rename on
      // either side is a crash on a machine nobody here has, so the two lists
      // are compared where it costs nothing.
      final ProcessResult symbols = Process.runSync(
        'x86_64-w64-mingw32-nm',
        <String>['-g', '${scratch.path}/single_instance_guard.cpp.o'],
      );
      final String exported = symbols.stdout.toString();
      final String dart = File(
        '$repoRoot/toolkit/dovetail_platform_channel/lib/src/instance/'
        'windows_single_instance.dart',
      ).readAsStringSync();
      for (final RegExpMatch match in RegExp(
        "'(Dovetail[A-Za-z]+)'",
      ).allMatches(dart)) {
        final String symbol = match.group(1)!;
        if (!exported.contains(' T $symbol')) {
          failed++;
          stdout.writeln(
            '  MISSING  $symbol — Dart looks it up and the DLL would not '
            'export it',
          );
        }
      }
    } finally {
      scratch.deleteSync(recursive: true);
    }
  }

  const List<String> crates = <String>[
    'toolkit/dovetail_rust_core/rust',
    'toolkit/dovetail_shortcut_channel/rust',
  ];
  const List<String> triples = <String>[
    'x86_64-pc-windows-msvc',
    'x86_64-unknown-linux-gnu',
  ];
  final String installed = Process.runSync('rustup', <String>[
    'target',
    'list',
    '--installed',
  ]).stdout.toString();

  for (final String triple in triples) {
    if (!installed.contains(triple)) {
      stdout.writeln('  absent   $triple — rustup target add $triple');
      continue;
    }
    for (final String crate in crates) {
      final ProcessResult checked = Process.runSync('cargo', <String>[
        'check',
        '--quiet',
        '--target',
        triple,
      ], workingDirectory: '$repoRoot/$crate');
      if (checked.exitCode != 0) {
        failed++;
        stdout.writeln('  FAILED   $crate for $triple');
        stdout.writeln(
          '           ${checked.stderr.toString().trim().split('\n').first}',
        );
      } else {
        stdout.writeln('  ok       $crate typechecks for $triple');
      }
    }
  }

  failed += _clippy(only: only);

  // `_pluginCoverage` le o manifesto de plugins de `product/vpn_desktop` e,
  // quando ele falta, o REGENERA com `flutter pub get --enforce-lockfile` —
  // que resolve o design system no repositorio irmao privado. Era a chamada
  // que fazia `cross --only toolkit` (`ci.yml`) nao ser toolkit-only.
  //
  // Pular dizendo por que, e nao em silencio: um alvo que sai verde tendo
  // deixado de checar e pior do que um que recusa.
  if (_selected(
    only,
  ).any(((String, String) each) => each.$1 == 'product/vpn_desktop')) {
    failed += _pluginCoverage();
  } else {
    stdout.writeln(
      '  skipped  plugin coverage — pede product/vpn_desktop, que resolve '
      'o design system no irmao privado',
    );
  }

  // Two vendored copies of an ARCHIVED dependency. They had already drifted
  // apart by seventeen files — cosmetically, as it turned out, but nobody
  // could tell without checking, and that is the whole problem with a
  // dependency whose upstream will never answer again.
  //
  // Compared in Dart, not with `diff`: diff is a Unix binary and the Windows
  // runner would silently lose this check.
  const List<String> copies = <String>[
    'product/desktop_core_bridge/cargokit',
    'toolkit/dovetail_shortcut_channel/cargokit',
  ];
  final List<String> drift = _driftBetween(
    '$repoRoot/${copies.first}',
    '$repoRoot/${copies.last}',
  );
  if (drift.isNotEmpty) {
    failed++;
    stdout.writeln('  DRIFTED  the two cargokit copies are not identical');
    for (final String line in drift.take(5)) {
      stdout.writeln('           $line');
    }
  } else {
    stdout.writeln('  ok       the two cargokit copies are identical');
  }

  stdout.writeln(failed == 0 ? '  ok' : '  $failed cross check(s) failed');
  return failed == 0 ? 0 : 1;
}

// ---------------------------------------------------------------- test

/// `--only <package>` narrows the run. Without it every red costs a full
/// pass to confirm, and a check that expensive to repeat is one people stop
/// repeating.
String? _only(List<String> arguments) {
  final int at = arguments.indexOf('--only');
  return at >= 0 && at + 1 < arguments.length ? arguments[at + 1] : null;
}

/// Quantos pacotes `dart` rodam ao mesmo tempo.
///
/// Nao nove: cada `dart test` ja bifurca as suites dele, entao nove de uma vez
/// sobrecarrega onze nucleos, e carga e o que faz o resto dos flakes flakear.
/// Tres foi onde o relogio parou de melhorar sem comprar variancia.
///
/// Sobrescrevivel por `DOVETAIL_LANES` — um runner com outra maquina embaixo
/// nao tem por que herdar o numero desta.
int get _lanes => math.max(
  1,
  int.tryParse(Platform.environment['DOVETAIL_LANES'] ?? '') ?? 3,
);

/// Quantas suites cada runner roda ao mesmo tempo, dentro de um pacote.
///
/// Explicito porque o default do runner e o numero de nucleos: com `_lanes`
/// pacotes rodando juntos, o total viram `_lanes x nucleos` processos de teste
/// disputando onze nucleos. Era essa multiplicacao — nao a concorrencia entre
/// pacotes por si — que produzia o vermelho intermitente.
///
/// O teto REAL hoje, medido com `ps` a cada 0,5s numa corrida: sao
/// `(_lanes + 1) x _suiteConcurrency` processos de teste — o pool `dart` de
/// `_lanes` pacotes e a cadeia `flutter` de um, rodando ao mesmo tempo. Com os
/// defaults, 16 em vez dos 12 de antes das duas trilhas. Dez corridas seguidas
/// verdes com esse teto (`tool/soak.sh 10`); e ele que o proximo a mexer aqui
/// tem de ler, nao o de antes.
int get _suiteConcurrency => math.max(
  1,
  int.tryParse(Platform.environment['DOVETAIL_SUITE_JOBS'] ?? '') ?? 4,
);

Future<_Run> _test({String? only}) async {
  stdout.writeln('── test ──');
  final Map<String, _PackageResult> results = <String, _PackageResult>{};
  final List<String> report = <String>[];
  bool failed = false;

  final List<(String, String)> wanted = _selected(only);

  // Duas trilhas ao mesmo tempo: um POOL de pacotes `dart` e uma CADEIA de
  // pacotes `flutter`, cada um pegando o proximo assim que termina.
  //
  // A serializacao do flutter continua, e pelo motivo de sempre: `flutter
  // test` sobe a ferramenta Flutter, que resolve pub, escreve `.dart_tool` e
  // monta um device, e varios concorrendo disputam o mesmo cache — foi de la
  // que saiu `FAILED product/vpn_desktop` com zero testes rodados numa
  // corrida e verde na seguinte. O que muda e que ela nao espera mais o pool
  // dart acabar: eram duas fases com uma barreira no meio, e os seis pacotes
  // flutter — que sao os lentos — comecavam so depois que o ultimo dart
  // terminasse. Isto acrescenta UM pacote concorrente, nao seis — e um pacote
  // sao `_suiteConcurrency` processos, entao o teto de processos subiu de
  // `_lanes x 4` para `(_lanes + 1) x 4`. O numero esta no comentario de
  // `_suiteConcurrency`, junto da medicao.
  //
  // Dentro de cada trilha, o mais longo primeiro. Com o mais longo despachado
  // por ultimo, a corrida inteira termina quando ele termina, e todo o resto
  // ja acabou faz tempo — `toolkit/dovetail_cli` era exatamente esse caso.
  //
  // A duracao vem da corrida anterior, gravada no run file. Na primeira vez
  // nao ha nenhuma, e o numero de testes declarados no baseline serve de
  // proxy; sem baseline tambem, a ordem declarada e o que sobra. Nada disto
  // afeta o veredito — so a ordem de despacho.
  //
  // Nao ha retry, e nao por esquecimento: retry torna verde compativel com
  // "nao provado", que e a unica patologia que este arquivo existe para
  // impedir. Flake que sobreviver a isto vira skip nomeado no baseline.
  final Map<String, int> lastSeen = _lastDurations();
  int cost(String package) => lastSeen[package] ?? 0;

  final List<(String, String)> dartTrack =
      wanted.where(((String, String) each) => each.$2 == 'dart').toList()..sort(
        ((String, String) a, (String, String) b) =>
            cost(b.$1).compareTo(cost(a.$1)),
      );
  final List<(String, String)> flutterTrack =
      wanted.where(((String, String) each) => each.$2 != 'dart').toList()..sort(
        ((String, String) a, (String, String) b) =>
            cost(b.$1).compareTo(cost(a.$1)),
      );

  final Map<String, int> tookMillis = <String, int>{};
  final List<_Outcome> outcomes = <_Outcome>[];

  Future<void> drain(List<(String, String)> queue, int width) async {
    int next = 0;
    Future<void> worker() async {
      while (true) {
        if (next >= queue.length) {
          return;
        }
        final (String package, String runner) = queue[next++];
        final Stopwatch watch = Stopwatch()..start();
        final _Outcome outcome = await _runPackage(package, runner);
        watch.stop();
        tookMillis[package] = watch.elapsedMilliseconds;
        outcomes.add(outcome);
        // Uma linha AGORA, e o bloco ordenado no fim. Medido: `── test ──`
        // em 0,19s e as doze linhas todas em 69s, dentro de 40 ms uma da
        // outra — um portão mudo por mais de um minuto parece travado, e o
        // reflexo é o Ctrl+C. O prefixo `…` distingue esta linha do relatório
        // final, que continua sendo o que se compara entre corridas.
        stdout.writeln(
          '  … ${outcome.failed ? 'FAILED' : 'ok'}  $package  '
          '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
        );
      }
    }

    await Future.wait(<Future<void>>[
      for (int i = 0; i < math.min(width, queue.length); i++) worker(),
    ]);
  }

  await Future.wait(<Future<void>>[
    drain(dartTrack, _lanes),
    drain(flutterTrack, 1),
  ]);

  {
    // Ordenado por pacote AQUI, na raiz, e nao so no `report`. Os workers
    // terminam em ordem que muda a cada corrida, e `results` herda essa ordem
    // como insercao do Map; `report.sort()` nao alcanca quem le `results`
    // direto — `_readmeRows` escreve MISSING ROW / ROW STALE iterando-o, e
    // `_compare` itera `run.results.keys`. Um relatorio que muda de ordem
    // entre corridas e um relatorio que ninguem compara.
    final List<_Outcome> done = outcomes.toList()
      ..sort((_Outcome a, _Outcome b) => a.package.compareTo(b.package));
    for (final _Outcome outcome in done) {
      results[outcome.package] = outcome.result;
      report.addAll(outcome.report);
      if (outcome.failed) {
        failed = true;
      }
    }
  }

  // Determinístico por CONSTRUÇÃO — os `_Outcome` já vêm ordenados por pacote
  // acima, e cada bloco (cabeçalho + detalhes) é emitido inteiro. Era um
  // `report.sort()` plano sobre todas as linhas: as de detalhe começam com onze
  // espaços e as de cabeçalho com dois, então no vermelho os nomes dos testes
  // flutuavam para o TOPO, acima de todo `FAILED`, sem dizer de qual dos doze
  // pacotes vinham. Reproduzido com dois pacotes quebrados de propósito.
  report.forEach(stdout.writeln);

  // A tabela do README, contra o que acabou de rodar. Aqui e nao no alvo
  // `readme` porque so a corrida sabe o numero de agora: o baseline fica para
  // tras toda vez que alguem escreve um teste, que e o caso normal.
  if (_readmeRows(File('$repoRoot/README.md').readAsStringSync(), results) >
      0) {
    failed = true;
  }

  // Escrito DEPOIS da checagem de linhas, para o `green` do cabecalho ser o
  // veredito final e nao um parcial: `bless` decide em cima dele.
  Directory('$repoRoot/dist').createSync(recursive: true);
  File('$repoRoot/$_runFile').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'run': _runHeader(complete: results.length == _packages.length, green: !failed),
      'took_ms': <String, Object?>{for (final String package in tookMillis.keys.toList()..sort()) package: tookMillis[package]},
      ..._encode(results),
    })}\n',
  );

  return _Run(results: results, failed: failed);
}

/// Quanto cada pacote levou na ultima corrida, em milissegundos.
///
/// So para ORDENAR o despacho — nunca entra em veredito. Um numero velho, ou
/// ausente, atrasa a corrida um pouco; nao a torna errada. Por isso lido sem
/// cerimonia e com queda para o baseline (numero de testes declarados como
/// proxy) e dai para a ordem declarada.
Map<String, int> _lastDurations() {
  for (final String file in <String>[_runFile, _baselineFile]) {
    final File candidate = File('$repoRoot/$file');
    if (!candidate.existsSync()) {
      continue;
    }
    try {
      final Object? decoded = jsonDecode(candidate.readAsStringSync());
      if (decoded is! Map<String, Object?>) {
        continue;
      }
      // Uma corrida `--only` grava duracoes de UM pacote. Usa-las deixaria os
      // outros onze com custo zero, e a ordem sairia quase invertida — o mais
      // longo por ultimo, que e exatamente o que esta ordenacao existe para
      // evitar. O cabecalho ja diz se a corrida foi completa; parcial cai para
      // o proxy do baseline.
      final Object? header = decoded['run'];
      final bool complete =
          header is! Map<String, Object?> || header['complete'] == true;
      // O arquivo INTEIRO, nao so o ramo das duracoes: o proxy por testes
      // declarados abaixo leria o mesmo arquivo parcial, acharia um pacote, e
      // devolveria — o baseline que o comentario promete nunca seria lido.
      if (!complete) {
        continue;
      }
      final Object? took = decoded['took_ms'];
      if (took is Map<String, Object?> && took.isNotEmpty) {
        return <String, int>{
          for (final MapEntry<String, Object?> each in took.entries)
            if (each.value is int) each.key: each.value! as int,
        };
      }
      // Sem duracao gravada ainda: o numero de testes declarados e o proxy
      // mais proximo que existe sem medir nada.
      // Tudo por `is`, nada por `as`: este arquivo nao afeta veredito, entao
      // um JSON com a forma errada nao pode derrubar a corrida. Com o cast, um
      // `"packages": {"x": 42}` matava o portao com TypeError ANTES do primeiro
      // teste — a leitura de uma dica de ordenacao virando a razao de nada
      // rodar.
      final Object? packages = decoded['packages'];
      if (packages is Map<String, Object?>) {
        final Map<String, int> proxy = <String, int>{};
        for (final MapEntry<String, Object?> package in packages.entries) {
          final Object? body = package.value;
          final Object? suites = body is Map<String, Object?>
              ? body['suites']
              : null;
          if (suites is! Map<String, Object?>) {
            continue;
          }
          int declared = 0;
          for (final Object? suite in suites.values) {
            final Object? count = suite is Map<String, Object?>
                ? suite['declared']
                : null;
            if (count is int) {
              declared += count;
            }
          }
          proxy[package.key] = declared;
        }
        if (proxy.isNotEmpty) {
          return proxy;
        }
      }
    } on FormatException {
      continue;
    }
  }
  return <String, int>{};
}

Future<_Outcome> _runPackage(String package, String runner) async {
  const _PackageResult nothing = _PackageResult(
    suites: <String, _Suite>{},
    failures: <String>[],
  );

  // A fresh checkout has no .dart_tool and `dart test` will not create one.
  // The push hook runs in a worktree, so this is the common case there.
  if (!File('$repoRoot/$package/.dart_tool/package_config.json').existsSync()) {
    // --enforce-lockfile: the locks are versioned, so a resolution that no
    // longer matches them is drift, not a detail to absorb quietly. Without
    // it the same commit resolves different graphs on different days and the
    // baseline slowly stops describing anything.
    final ProcessResult resolved = await Process.run(runner, <String>[
      'pub',
      'get',
      '--enforce-lockfile',
    ], workingDirectory: '$repoRoot/$package');
    if (resolved.exitCode != 0) {
      return _Outcome(
        package: package,
        result: nothing,
        failed: true,
        report: <String>['  UNRESOLVED $package'],
      );
    }
  }

  final ProcessResult ran = await Process.run(
    runner,
    // `--concurrency` explicito: o default dos dois runners e o numero de
    // nucleos, e com varios pacotes em paralelo isso multiplica em vez de
    // dividir. O numero fica num lugar so, e `DOVETAIL_SUITE_JOBS` o move.
    <String>['test', '--reporter=json', '--concurrency=$_suiteConcurrency'],
    workingDirectory: '$repoRoot/$package',
    environment: <String, String>{'DOVETAIL_REPO_ROOT': repoRoot},
  );
  final _PackageResult parsed = _parse(
    ran.stdout.toString(),
    packageDirectory: '$repoRoot/$package',
  );

  final int declared = parsed.suites.values
      .map((_Suite s) => s.declared)
      .fold(0, (int a, int b) => a + b);
  final int skipped = parsed.suites.values
      .map((_Suite s) => s.skips.length)
      .fold(0, (int a, int b) => a + b);

  final List<String> report = <String>[];
  bool failed = false;

  if (ran.exitCode != 0) {
    failed = true;
    report.add('  FAILED   $package  (exit ${ran.exitCode})');
    for (final String line in parsed.failures) {
      report.add('           $line');
    }
    // Sem esta parte o relatorio saia vazio, e foi assim que
    // `FAILED product/vpn_desktop` apareceu com zero testes rodados e nenhuma
    // pista: o runner morreu antes do primeiro objeto JSON, entao
    // `parsed.failures` estava vazio e o unico sinal — o stderr — era jogado
    // fora. Um portao que fica vermelho sem dizer por que e um portao que as
    // pessoas param de ler.
    if (parsed.failures.isEmpty) {
      final List<String> noise = const LineSplitter()
          .convert(ran.stderr.toString())
          .map((String line) => line.trimRight())
          .where((String line) => line.isNotEmpty)
          .toList();
      if (noise.isEmpty) {
        report.add(
          '           the runner printed nothing on stderr and reported no '
          'test failure — it died before the suite loaded',
        );
      } else {
        for (final String line in noise.take(8)) {
          report.add('           $line');
        }
        if (noise.length > 8) {
          report.add('           … ${noise.length - 8} more line(s)');
        }
      }
    }
  } else {
    report.add(
      '  ok       $package  '
      '${parsed.suites.length} suites, $declared declared, $skipped skipped',
    );
  }

  // A suite the runner collected but git does not track counts here and
  // exists nowhere else. It has happened: keygen_command_test.dart sat
  // untracked with six tests in it.
  for (final String suite in parsed.suites.keys) {
    if (!_isTracked('$package/$suite')) {
      failed = true;
      report.add(
        '  UNTRACKED $package/$suite — it counts here and exists nowhere '
        'else. git add it, or delete it.',
      );
    }
  }

  return _Outcome(
    package: package,
    result: parsed,
    failed: failed,
    report: report,
  );
}

/// The README's table is the first page anybody reads, and a number typed by
/// hand there ages the next day: it claimed 532 tests when there were 997.
/// This does not rewrite it — it refuses when it and the baseline disagree,
/// and prints the number to put in.
int _readme() {
  stdout.writeln('── readme ──');
  final File baseline = File('$repoRoot/$_baselineFile');
  if (!baseline.existsSync()) {
    stderr.writeln('no $_baselineFile. Run: dart tool/verify.dart bless');
    return 1;
  }
  final Map<String, _PackageResult> recorded = _decode(
    jsonDecode(baseline.readAsStringSync()) as Map<String, Object?>,
  );

  int declared = 0;
  int skipped = 0;
  for (final _PackageResult package in recorded.values) {
    for (final _Suite suite in package.suites.values) {
      declared += suite.declared;
      skipped += suite.skips.length;
    }
  }

  final String text = File('$repoRoot/README.md').readAsStringSync();
  final String claim = '**$declared testes Dart declarados, $skipped pulados**';

  if (text.contains(claim)) {
    stdout.writeln('  ok  $declared declarados, $skipped pulados');
    return 0;
  }
  stdout.writeln('  README.md and the baseline disagree. It should say:');
  stdout.writeln('    $claim');
  return 1;
}

/// A tabela do README linha por linha, contra o que ACABOU de rodar.
///
/// O total ja era conferido contra o baseline, e mesmo assim as linhas
/// envelheceram quatro vezes num dia: 236 quando eram 261, 275 quando eram
/// 287, 11 quando eram 15. O baseline nao pega isso, porque ele tambem fica
/// para tras quando alguem escreve teste — e escrever teste e o caso normal.
///
/// A corrida sabe. Cada pacote que rodou traz o numero de verdade, e a tabela
/// e a primeira coisa que alguem le sobre este repositorio.
int _readmeRows(String readme, Map<String, _PackageResult> ran) {
  final RegExp row = RegExp(r'^\| `([^`]+)` \| (\d+) Dart', multiLine: true);
  final Map<String, int> claimed = <String, int>{
    for (final RegExpMatch match in row.allMatches(readme))
      match.group(1)!: int.parse(match.group(2)!),
  };

  int wrong = 0;
  final List<String> unchecked = <String>[];

  for (final MapEntry<String, _PackageResult> package in ran.entries) {
    // So o que o git rastreia. Um clone limpo rodou 94 testes de um pacote
    // cuja linha dizia 111, e a diferenca eram tres arquivos de teste que
    // existem nesta maquina e em lugar nenhum: contando-os, a tabela promete
    // a quem clona um numero que ele nao alcanca. A corrida ja grita
    // UNTRACKED por eles; a tabela e sobre o que viaja.
    final int declared = package.value.suites.entries
        .where(
          (MapEntry<String, _Suite> suite) =>
              _isTracked('${package.key}/${suite.key}'),
        )
        .map((MapEntry<String, _Suite> suite) => suite.value.declared)
        .fold(0, (int a, int b) => a + b);
    final int? says = claimed[package.key];

    if (says == null) {
      wrong++;
      stdout.writeln(
        '  MISSING ROW  ${package.key} ran and has no row in the README '
        '($declared Dart)',
      );
    } else if (says != declared) {
      wrong++;
      stdout.writeln(
        '  ROW STALE    ${package.key} says $says Dart, and $declared ran',
      );
    }
  }

  for (final String package in claimed.keys) {
    if (!ran.containsKey(package)) {
      unchecked.add(package);
    }
  }
  if (unchecked.isNotEmpty) {
    // Ordenado: uma linha de relatorio que muda de ordem entre corridas e uma
    // linha que ninguem compara. Acontece de proposito com `--only`.
    unchecked.sort();
    stdout.writeln('  unchecked    ${unchecked.join(', ')} — did not run');
  }
  return wrong;
}

// ---------------------------------------------------------------- baseline

int _compare(_Run run) {
  stdout.writeln('── baseline ──');
  final File file = File('$repoRoot/$_baselineFile');
  if (!file.existsSync()) {
    stderr.writeln(
      'no $_baselineFile yet. Write it with: dart tool/verify.dart bless',
    );
    return 1;
  }

  final Map<String, _PackageResult> recorded = _decode(
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
  );
  final List<String> problems = <String>[];
  final List<String> news = <String>[];

  final bool partial = run.results.length < recorded.length;
  for (final MapEntry<String, _PackageResult> entry in recorded.entries) {
    final _PackageResult? now = run.results[entry.key];
    if (now == null) {
      // A --only run compares what it ran. Calling the rest "gone" would
      // train people to ignore the word.
      if (!partial) {
        problems.add('PACKAGE GONE  ${entry.key} did not run at all');
      }
      continue;
    }
    for (final MapEntry<String, _Suite> was in entry.value.suites.entries) {
      final _Suite? is_ = now.suites[was.key];
      final String where = '${entry.key}/${was.key}';
      if (is_ == null) {
        problems.add(
          'SUITE GONE    $where — it was collected before and was not now',
        );
        continue;
      }
      // Down is the patology. Up is somebody writing a test.
      if (is_.declared < was.value.declared) {
        problems.add(
          'COUNT DOWN    $where declared ${was.value.declared}, now '
          '${is_.declared} — tests stopped being registered',
        );
      } else if (is_.declared > was.value.declared) {
        news.add(
          'new tests     $where ${was.value.declared} → ${is_.declared}',
        );
      }
      for (final MapEntry<String, String> skip in was.value.skips.entries) {
        final String? reason = is_.skips[skip.key];
        if (reason == null) {
          // News, not a problem, and for the same reason a rising count is:
          // a skip that stops happening means MORE was proven, never less.
          // It is also the only honest answer to the environment. The set of
          // legitimate skips depends on what is built — the baseline was
          // recorded in a cold worktree with no Rust crates and no macOS app,
          // and in a tree that has been building all day those same tests
          // run. Failing on that would train people to bless noise, and a
          // baseline blessed out of habit guards nothing.
          news.add('skip gone     $where "${skip.key}"');
        } else if (reason != skip.value) {
          problems.add(
            'REASON MOVED  $where "${skip.key}"\n'
            '                was: ${skip.value}\n'
            '                now: $reason',
          );
        }
      }
      for (final MapEntry<String, String> skip in is_.skips.entries) {
        if (!was.value.skips.containsKey(skip.key)) {
          problems.add('SKIP NEW      $where "${skip.key}" — ${skip.value}');
        }
      }
    }
  }
  for (final String package in run.results.keys) {
    if (!recorded.containsKey(package)) {
      news.add('new package   $package');
      continue;
    }
    // Suite nova, e os skips que ela traz.
    //
    // O laco de cima itera o BASELINE, entao um arquivo de teste novo nao era
    // nem problema nem noticia: dez testes pulados podiam entrar sem que uma
    // linha aparecesse, e o baseline so aprenderia deles no proximo bless —
    // gravando-os como se sempre tivessem estado ali. `SUITE NEW` e noticia,
    // nao problema, pela mesma regra do resto: escrever teste e o caso normal.
    final _PackageResult was = recorded[package]!;
    for (final MapEntry<String, _Suite> is_
        in run.results[package]!.suites.entries) {
      if (was.suites.containsKey(is_.key)) {
        continue;
      }
      final int skips = is_.value.skips.length;
      news.add(
        'SUITE NEW     $package/${is_.key} — ${is_.value.declared} declared'
        '${skips == 0 ? '' : ', $skips skipped'}',
      );
    }
  }

  for (final String line in news) {
    stdout.writeln('  $line');
  }
  for (final String line in problems) {
    stdout.writeln('  $line');
  }
  if (problems.isEmpty) {
    stdout.writeln('  ok');
    return 0;
  }
  stdout.writeln(
    '\n  ${problems.length} difference(s). If they are intended: '
    'dart tool/verify.dart bless',
  );
  return 1;
}

int _bless(List<String> arguments) {
  final File run = File('$repoRoot/$_runFile');
  if (!run.existsSync()) {
    stderr.writeln('no $_runFile. Run: dart tool/verify.dart test');
    return 1;
  }

  // Um `cp` cego era o que isto fazia, e o arquivo de origem nao dizia nada
  // sobre si. Um `--only` deixa para tras uma corrida de um pacote — chegou a
  // ter 82 bytes aqui — e abencoa-la apagaria os outros onze do baseline sem
  // uma palavra. Uma corrida vermelha declara menos do que devia, e gravar
  // isso e gravar a falha como se fosse o estado certo.
  //
  // `--force` existe porque gravar de um clone frio noutro diretorio e o
  // procedimento documentado em docs/ci.md, e ali o commit e outro de
  // proposito. O que ele nao dispensa e a corrida ser completa e verde.
  final bool force = arguments.contains('--force');
  final Object? decoded = jsonDecode(run.readAsStringSync());
  final Map<String, Object?>? header =
      (decoded is Map<String, Object?> ? decoded['run'] : null)
          as Map<String, Object?>?;

  if (header == null) {
    stderr.writeln('$_runFile carries no "run" header.');
    stderr.writeln(
      '  It was written by an older verify, and nothing about it can be '
      'checked — not whether it was complete, green, or from this tree.',
    );
    stderr.writeln('  Run: dart tool/verify.dart test');
    return 1;
  }
  if (header['complete'] != true) {
    final Object? packages = (decoded! as Map<String, Object?>)['packages'];
    final int ran = packages is Map<String, Object?> ? packages.length : 0;
    stderr.writeln('$_runFile is a partial run.');
    stderr.writeln(
      '  It has $ran of ${header['packages_expected']} packages — a --only '
      'run. Blessing it would drop the rest of the baseline.',
    );
    stderr.writeln('  Run the whole thing: dart tool/verify.dart test');
    return 1;
  }
  if (header['green'] != true) {
    stderr.writeln('$_runFile is a red run.');
    stderr.writeln(
      '  A failing run declares fewer tests than it should — that is what '
      'failing means — so blessing it records the failure as the truth.',
    );
    return 1;
  }
  final String? sha = header['commit'] as String?;
  final String head = Process.runSync('git', <String>[
    'rev-parse',
    'HEAD',
  ], workingDirectory: repoRoot).stdout.toString().trim();
  if (!force && sha != null && head.isNotEmpty && sha != head) {
    stderr.writeln('$_runFile is from another commit.');
    stderr.writeln('  run:  $sha');
    stderr.writeln('  HEAD: $head');
    stderr.writeln(
      '  Recording a cold tree from elsewhere is the documented procedure '
      '(docs/ci.md), and there the commit differs on purpose: pass --force.',
    );
    return 1;
  }

  // Só os pacotes. O cabeçalho descreve a CORRIDA — commit, verde, completa —
  // e o baseline descreve um ESTADO: gravar o sha ali poria no diff, a cada
  // bless, uma linha que muda sozinha e não quer dizer nada.
  final Map<String, Object?> body = <String, Object?>{
    'packages': (decoded! as Map<String, Object?>)['packages'],
  };
  File('$repoRoot/$_baselineFile')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(body)}\n',
    );
  stdout.writeln('wrote $_baselineFile from $_runFile');
  stdout.writeln('Read the diff before committing it: git diff $_baselineFile');
  return 0;
}

/// `cargo fmt --check`, pelo mesmo motivo que o `dart format`.
///
/// Nenhum destes tres crates e copia vendorizada — o `cargokit` e Dart —, entao
/// aqui nao ha exclusao a fazer: o que estiver torto e nosso.
int _rustFormat({String? only}) {
  if (_which('cargo') == null) {
    return 0;
  }
  final List<String> crates = <String>[
    for (final String crate in const <String>[
      'toolkit/dovetail_rust_core/rust',
      'toolkit/dovetail_shortcut_channel/rust',
      'product/desktop_core_bridge/rust',
    ])
      if (only == null || crate.contains(only)) crate,
  ];

  final List<String> crooked = <String>[];
  for (final String crate in crates) {
    final ProcessResult checked = Process.runSync('cargo', <String>[
      'fmt',
      '--check',
    ], workingDirectory: '$repoRoot/$crate');
    if (checked.exitCode != 0) {
      crooked.add(crate);
    }
  }

  if (crooked.isEmpty) {
    return 0;
  }
  stdout.writeln('  UNFORMATTED (rust)');
  for (final String crate in crooked) {
    stdout.writeln('           $crate — run: cd $crate && cargo fmt');
  }
  return 1;
}

/// O FFI atravessa de verdade?
///
/// Tudo o mais aqui prova forma: que compila, que tipa, que os 51 metodos do
/// nucleo estao na ponte, que o gerado bate com o Rust. Nada disso prova que
/// uma chamada Dart chega no Rust e volta com o valor — e essa prova existia,
/// em `example/integration_test/bridge_test.dart`, rodada **a mao**.
///
/// Cinco testes: `isSupported`, uma chamada assincrona que devolve a versao do
/// crate, o contrato do helper, `ensureInitialized` idempotente, e uma chamada
/// `#[frb(sync)]` respondendo sem passar por Future. Custam 53 segundos porque
/// sobem um app de verdade, e e por isso que este alvo nao esta no `fast`.
///
/// **Abre uma janela.** Nao ha como nao abrir: o `integration_test` do Flutter
/// e o app rodando, e o valor do teste vem justamente disso.
/// A esteira macOS inteira contra um host local: assina o `.app` de dentro
/// para fora, monta e assina o dmg, gera o `.app.tar.gz` que o updater
/// instala, escreve o manifesto, serve o `dist/` por https com uma CA privada
/// e pergunta ao `probe` — o mesmo parser e o mesmo verificador do app — se o
/// endpoint serve o que o cliente le.
///
/// Os substitutos das tres coisas que nao existem (chave de producao, host,
/// Developer ID) seguem o mesmo contrato do real, e o script diz o que NAO
/// prova: Gatekeeper, notarizacao, DNS. Ver docs/release-simulado.md.
///
/// Pula quando nao ha `.app` construido — e o caso do worktree do pre-push, e
/// de qualquer clone limpo — e diz isso. Construir aqui custaria dez minutos
/// por push; provar a esteira sobre um build que existe custa um minuto. E
/// pula sob um `--only` que nao pede o produto, como frb e ffi: sem isso, um
/// `all --only dovetail_form_validation` — que existe para custar um segundo — pagava
/// a esteira inteira.
int _releaseProof({String? only}) {
  stdout.writeln('── release ──');
  const String script = 'tool/ci/prove_update.sh';
  const String product = 'product/vpn_desktop';
  const String built =
      '$product/build/macos/Build/Products/Release/vpn_desktop.app';

  // O mesmo contrato do frb e do ffi: um `--only` que nao seleciona o produto
  // nao paga um minuto de esteira. Sem isto, `all --only dovetail_form_validation` —
  // que existe para custar um segundo — rodava a prova inteira.
  if (only != null &&
      !_selected(only).any(((String, String) each) => each.$1 == product)) {
    stdout.writeln('  skipped  pede $product (--only)');
    return 0;
  }
  if (!Platform.isMacOS) {
    stdout.writeln(
      '  skipped  esta prova e da esteira macOS, e este host e '
      '${Platform.operatingSystem}',
    );
    return 0;
  }
  if (!Directory('$repoRoot/$built').existsSync()) {
    stdout.writeln(
      '  skipped  sem $built — rode `dovetail build` em product/vpn_desktop '
      'para a esteira ter o que assinar',
    );
    return 0;
  }
  for (final String tool in <String>['openssl', 'minisign', 'python3']) {
    if (_which(tool) == null) {
      stdout.writeln('  MISSING  $tool');
      return 1;
    }
  }

  final ProcessResult ran = Process.runSync('bash', <String>[
    script,
    '--host',
    'macos',
  ], workingDirectory: repoRoot);
  final String output = '${ran.stdout}${ran.stderr}';

  if (ran.exitCode == 0 && output.contains('prove_update: ok')) {
    final int checks = RegExp(
      r'^  ok ',
      multiLine: true,
    ).allMatches(output).length;
    stdout.writeln(
      '  ok       $checks checks: signed, served over https, verified by the '
      'client parser',
    );
    return 0;
  }

  stdout.writeln('  FAILED   $script exited ${ran.exitCode}');
  for (final String line
      in output
          .split('\n')
          .where(
            (String line) => line.contains('FAILED') || line.startsWith('== '),
          )) {
    stdout.writeln('    $line');
  }
  return 1;
}

int _ffiCrosses() {
  stdout.writeln('── ffi ──');
  const String example = 'product/desktop_core_bridge/example';

  if (!Platform.isMacOS) {
    stdout.writeln(
      '  skipped  este alvo roda o app de verdade, e o unico device provado '
      'aqui e macOS',
    );
    return 0;
  }
  if (_which('flutter') == null) {
    stdout.writeln('  MISSING  flutter');
    return 1;
  }

  final ProcessResult ran = Process.runSync('flutter', <String>[
    'test',
    'integration_test/bridge_test.dart',
    '-d',
    'macos',
  ], workingDirectory: '$repoRoot/$example');

  final String output = ran.stdout.toString();
  final RegExpMatch? passed = RegExp(
    r'\+(\d+): All tests passed',
  ).firstMatch(output);

  if (ran.exitCode == 0 && passed != null) {
    stdout.writeln(
      '  ok       ${passed.group(1)} crossings, Dart to Rust and back',
    );
    return 0;
  }

  stdout.writeln('  FAILED   the FFI seam did not answer');
  for (final String line
      in const LineSplitter()
          .convert(output.isEmpty ? ran.stderr.toString() : output)
          .where(
            (String line) =>
                line.contains('Error') ||
                line.contains('Failed') ||
                line.contains('Exception'),
          )
          .take(6)) {
    stdout.writeln('           ${line.trim()}');
  }
  return 1;
}

/// A versao pinada da runtime do flutter_rust_bridge.
///
/// Lida do `Cargo.toml` em vez de escrita aqui: dois lugares para o mesmo
/// numero e um lugar para eles discordarem.
String get _frbPinned {
  final String cargo = File(
    '$repoRoot/product/desktop_core_bridge/rust/Cargo.toml',
  ).readAsStringSync();
  final RegExpMatch? pinned = RegExp(
    r'flutter_rust_bridge\s*=\s*"=([0-9.]+)"',
  ).firstMatch(cargo);
  return pinned?.group(1) ?? '';
}

/// O CLI que gera e a runtime que executa tem de ser a mesma versao.
///
/// O CLI e instalado global (`cargo install`) e a runtime e pinada no
/// `Cargo.toml`. Com versoes diferentes, o codigo gerado nao casa com a
/// runtime que o executa — e o frb tem uma checagem propria que dispara **em
/// tempo de execucao**, no app de quem baixou, com uma mensagem sobre hash de
/// conteudo que nao diz nada sobre a causa.
///
/// Pior: quem tem o CLI errado regenera e **commita** codigo que quebra na
/// maquina de todos os outros. E o "funciona na minha maquina" mais caro deste
/// stack, porque a diferenca esta fora da arvore.
int _codegenVersionMatchesRuntime() {
  final String pinned = _frbPinned;
  if (pinned.isEmpty) {
    stdout.writeln(
      '  FAILED   could not read the pinned flutter_rust_bridge version from '
      'rust/Cargo.toml',
    );
    return 1;
  }

  final ProcessResult asked = Process.runSync(
    'flutter_rust_bridge_codegen',
    <String>['--version'],
  );
  final RegExpMatch? installed = RegExp(
    r'([0-9]+\.[0-9]+\.[0-9]+)',
  ).firstMatch(asked.stdout.toString());

  if (installed == null) {
    stdout.writeln(
      '  FAILED   flutter_rust_bridge_codegen --version said '
      'nothing a version could be read from',
    );
    return 1;
  }
  if (installed.group(1) == pinned) {
    stdout.writeln('  ok       codegen $pinned matches the pinned runtime');
    return 0;
  }

  stdout.writeln(
    '  MISMATCH codegen ${installed.group(1)} against runtime $pinned',
  );
  stdout.writeln(
    '           Generated code from the wrong CLI fails at RUNTIME, in the '
    'app of whoever downloaded it, with a content-hash message that names '
    'no cause. Fix the tool, not the pin:',
  );
  stdout.writeln(
    '           cargo install flutter_rust_bridge_codegen --version $pinned',
  );
  return 1;
}

/// A ponte gerada esta em sincronia com o Rust que a gerou?
///
/// Este e o precipicio de DX deste stack, e foi medido em vez de suposto:
/// acrescente `pub fn nova_coisa()` em `rust/src/api/`, NAO rode o codegen, e
/// o `cargo check` passa. O `frb_generated.rs` continua valido, a app continua
/// compilando, e o metodo simplesmente **nao existe do lado Dart** — sem erro
/// em lugar nenhum. Quem escreveu a funcao vai procurar por que
/// `core.novaCoisa()` nao existe, e a resposta e "rode o codegen", que nada
/// diz.
///
/// O jeito de conferir e gerar e comparar. Nao ha como pedir ao codegen que
/// escreva fora do pacote — ele resolve `dart_output` contra a raiz Dart e
/// recusa —, entao a checagem gera NO LUGAR e restaura depois. Por isso ela
/// recusa comecar com esses caminhos sujos: com mudanca em curso ali, nao ha
/// como distinguir defasagem de trabalho.
int _bridgeIsGenerated() {
  stdout.writeln('── frb ──');
  const String package = 'product/desktop_core_bridge';
  const List<String> generated = <String>[
    '$package/lib/src/rust',
    '$package/rust/src/frb_generated.rs',
  ];

  if (_which('flutter_rust_bridge_codegen') == null) {
    stdout.writeln(
      '  absent   flutter_rust_bridge_codegen — install with: '
      'cargo install flutter_rust_bridge_codegen --version $_frbPinned',
    );
    return 0;
  }

  final int mismatched = _codegenVersionMatchesRuntime();
  if (mismatched != 0) {
    return mismatched;
  }

  final String dirty = _git(<String>['status', '--porcelain', ...generated]);
  if (dirty.trim().isNotEmpty) {
    stdout.writeln(
      '  skipped  the generated bridge has uncommitted changes, so stale '
      'cannot be told from work in progress',
    );
    return 0;
  }

  final ProcessResult ran = Process.runSync(
    'flutter_rust_bridge_codegen',
    <String>['generate'],
    workingDirectory: '$repoRoot/$package',
  );

  if (ran.exitCode != 0) {
    stdout.writeln('  FAILED   codegen did not run');
    stdout.writeln(
      '           ${ran.stderr.toString().trim().split('\n').last}',
    );
    return 1;
  }

  final String drift = _git(<String>['status', '--porcelain', ...generated]);
  if (drift.trim().isEmpty) {
    stdout.writeln('  ok       the bridge matches the Rust that generates it');
    return 0;
  }

  // Restaura: um portao que edita a arvore de quem o rodou e um portao que
  // assusta. O que ele deve fazer e dizer o comando.
  _git(<String>['checkout', '--', ...generated]);
  stdout.writeln('  STALE    the generated bridge is behind rust/src/api/');
  for (final String line in const LineSplitter().convert(drift).take(6)) {
    stdout.writeln('           ${line.trim()}');
  }
  stdout.writeln(
    '           Run: cd $package && flutter_rust_bridge_codegen generate',
  );
  return 1;
}

/// Os testes que rodam em Rust.
///
/// O portao tinha `cargo check` e `cargo clippy` e nao tinha `cargo test`, e
/// existem 40 testes em Rust neste repositorio: a bomba de eventos do
/// `dovetail_rust_core` e a maquina de estados do atalho global. Compilar sem avisos
/// nao e o mesmo que passar, e o README sempre disse "testes Dart declarados"
/// justamente porque estes ficavam de fora da contagem — o que era honesto
/// sobre o numero e calado sobre a lacuna.
///
/// Nao entram no baseline: aquele arquivo guarda suite Dart, com o nome do
/// teste e o motivo de cada skip, e o `cargo test` nao fala essa lingua. Aqui
/// o que se prende e passar.
int _rustTests({String? only}) {
  stdout.writeln('── rust ──');
  if (_which('cargo') == null) {
    stdout.writeln('  MISSING  cargo');
    return 1;
  }

  // `--only <substr>` narrows the crates, like `test --only` does for
  // packages. The CI legs that are not macOS use it to prove the toolkit
  // crates on their host and leave `product/desktop_core_bridge` out: that
  // crate drags the example-rust crates by path, and none of them has
  // ever compiled for a Linux or Windows host — proving that is the app-on-
  // Windows/Linux item, not the gate-on-Windows/Linux item.
  const List<String> allCrates = <String>[
    'toolkit/dovetail_rust_core/rust',
    'toolkit/dovetail_shortcut_channel/rust',
    'product/desktop_core_bridge/rust',
  ];
  final List<String> crates = only == null
      ? allCrates
      : allCrates.where((String crate) => crate.contains(only)).toList();

  int failed = 0;
  for (final String crate in crates) {
    final ProcessResult ran = Process.runSync('cargo', <String>[
      'test',
      '--quiet',
    ], workingDirectory: '$repoRoot/$crate');

    final Iterable<String> results = const LineSplitter()
        .convert(ran.stdout.toString())
        .where((String line) => line.startsWith('test result:'));

    int passed = 0;
    for (final String line in results) {
      final RegExpMatch? match = RegExp(r'(\d+) passed').firstMatch(line);
      passed += int.parse(match?.group(1) ?? '0');
    }

    if (ran.exitCode != 0) {
      failed++;
      stdout.writeln('  FAILED   $crate');
      for (final String line
          in const LineSplitter()
              .convert(ran.stdout.toString())
              .where(
                (String line) =>
                    line.contains('FAILED') || line.startsWith('---- '),
              )
              .take(6)) {
        stdout.writeln('           ${line.trim()}');
      }
    } else {
      stdout.writeln('  ok       $crate  $passed passed');
    }
  }

  // O `desktop_core_bridge/rust` entrou depois: ele e repasse, e por isso
  // ficou sem teste tanto tempo. Mas o mapeamento de `CoreError` para
  // `CoreFailure` nao e repasse — e decisao, e a interface de erro do app
  // inteiro se apoia nela.
  failed += _rustConventions(crates);
  stdout.writeln(failed == 0 ? '  ok' : '  $failed crate(s) failed');
  return failed == 0 ? 0 : 1;
}

/// As convencoes de Rust que os projetos de optimas compartilham, cobradas
/// aqui e nao no README de alguem.
///
/// Os scripts sao os MESMOS que o `dovetail new` instala no projeto gerado, e
/// os mesmos que o example-rust roda — uma fonte, tres consumidores. O
/// dovetail apontava para eles no template e nunca os aplicava em si: o
/// toolkit pregava o que nao praticava, e as 36 arquivos das crates daqui
/// nunca tinham passado por nenhum deles.
///
/// `check_no_comments.sh` fica FORA por decisao escrita: neste repositorio o
/// comentario que registra o defeito que motivou o codigo e o valor do
/// arquivo, e nao um resto que deveria estar no corpo do PR. Os outros cinco
/// valem — tamanho, TODO, identificador em ingles, url fixa, dependencia
/// concreta —, e sao incrementais: so olham o que mudou desde a base.
int _rustConventions(List<String> crates) {
  const String runner = 'tool/sdk/templates/app/scripts/checks/rust/run_all.sh';
  if (!File('$repoRoot/$runner').existsSync()) {
    stdout.writeln('  MISSING  $runner');
    return 1;
  }
  if (crates.isEmpty) {
    return 0;
  }

  final ProcessResult ran = Process.runSync(
    'bash',
    <String>[runner],
    workingDirectory: repoRoot,
    environment: <String, String>{
      'RUST_DIRS': crates.join(' '),
      'PULAR_CHECKS': 'check_no_comments.sh',
    },
  );
  final String output = '${ran.stdout}${ran.stderr}';

  if (ran.exitCode == 0) {
    final int checked = RegExp(
      r'^✅ check_',
      multiLine: true,
    ).allMatches(output).length;
    stdout.writeln('  ok       $checked convenções, nas crates desta corrida');
    return 0;
  }

  stdout.writeln('  FAILED   as convenções de Rust');
  for (final String line
      in const LineSplitter()
          .convert(output)
          .where(
            (String line) => line.startsWith('❌') || line.startsWith('   '),
          )
          .take(10)) {
    stdout.writeln('           ${line.trim()}');
  }
  return 1;
}

/// `cargo check` diz que compila. `clippy` diz o resto.
///
/// O portao rodava so o check, e clippy achou coisa de verdade quando foi
/// rodado a mao pela primeira vez: um `IoError::new(ErrorKind::Other, _)` que
/// tem forma propria ha versoes, e um `cfg` que o flutter_rust_bridge expande
/// e ninguem tinha declarado.
///
/// So conta o que mora NESTE repositorio. Os crates do produto entram por
/// caminho a partir de `../example-rust`, e o clippy linta dependencia por
/// caminho junto — quatorze avisos de `crates/core/src/apps.rs` apareceriam
/// aqui como se fossem nossos, e o portao que acusa o que voce nao pode
/// consertar e um portao que se aprende a ignorar.
int _clippy({String? only}) {
  if (_which('cargo') == null) {
    stdout.writeln('  absent   cargo — clippy nao roda');
    return 0;
  }

  // Narrowed by the same `--only <substr>` that `rust` accepts, for the same
  // reason: the CI legs that are not macOS lint the toolkit crates and leave
  // the product crate for the machine that can compile it.
  const List<String> allCrates = <String>[
    'toolkit/dovetail_rust_core/rust',
    'toolkit/dovetail_shortcut_channel/rust',
    'product/desktop_core_bridge/rust',
  ];
  final List<String> crates = only == null
      ? allCrates
      : allCrates.where((String crate) => crate.contains(only)).toList();

  int failed = 0;
  for (final String crate in crates) {
    final ProcessResult linted = Process.runSync('cargo', <String>[
      'clippy',
      '--all-targets',
      '--message-format=short',
    ], workingDirectory: '$repoRoot/$crate');

    // Caminho relativo e nosso; caminho absoluto e de dependencia por caminho,
    // que o cargo imprime a partir da raiz e mora em outro repositorio.
    final List<String> ours = const LineSplitter()
        .convert(linted.stderr.toString())
        .where(
          (String line) =>
              line.contains(': warning: ') || line.contains(': error: '),
        )
        .where((String line) => !line.startsWith('/'))
        .toList();

    if (linted.exitCode != 0 && ours.isEmpty) {
      failed++;
      stdout.writeln('  FAILED   clippy could not run in $crate');
      continue;
    }
    if (ours.isEmpty) {
      stdout.writeln('  ok       $crate is clippy-clean');
      continue;
    }
    failed++;
    stdout.writeln('  LINT     $crate');
    for (final String line in ours.take(8)) {
      stdout.writeln('           ${line.trim()}');
    }
  }
  return failed;
}

/// Plugin capabilities the product ships without on some desktop platform.
///
/// A gap here is invisible from this Mac: the Dart still compiles, the build
/// still succeeds, and the missing implementation surfaces as a
/// MissingPluginException on a machine nobody here has. Reading the plugin
/// manifest costs nothing and turns that into a fact with a name.
///
/// Federated plugins are counted as one capability — `url_launcher_macos`,
/// `url_launcher_windows` and `url_launcher_linux` are three packages and one
/// answer — so only the suffix is stripped, not the meaning.
const Set<String> _federatedSuffixes = <String>{'_macos', '_windows', '_linux'};

/// Known gaps, each with the reason it is known. A gap that is NOT here fails
/// the target; one that is here is reported and passes, because the fix lives
/// in another repository and a gate that stays red is a gate nobody reads.
const Map<String, String> _acceptedPluginGaps = <String, String>{
  'dovetail_platform_channel':
      'windows only, on purpose: the single-instance guard needs C++ only '
      'there, and this is our own plugin',
  'gtk':
      'a transitive dependency of the Linux implementations, Linux by '
      'definition',
  'mobile_scanner':
      'macOS only, and no Windows or Linux implementation exists. It arrives '
      'through the design system barrel, which exports qr_scanner_view. The '
      'desktop product has no QR feature at all — zero of the 818 text keys '
      'mention one — so nothing calls it. It would surface as a '
      'MissingPluginException on Windows, and the fix is in the design '
      'system, not here.',
};

int _pluginCoverage() {
  const String manifest = 'product/vpn_desktop/.flutter-plugins-dependencies';
  File file = File('$repoRoot/$manifest');
  if (!file.existsSync()) {
    // A clean clone has no generated manifest, and a check that quietly
    // stands down on the clean clone is a check that does not exist in CI —
    // the only place where every run starts clean. Generate it with the same
    // locked resolution the test lane uses, and refuse when it still cannot
    // be produced instead of going green without looking.
    final ProcessResult resolved = Process.runSync('flutter', <String>[
      'pub',
      'get',
      '--enforce-lockfile',
    ], workingDirectory: '$repoRoot/product/vpn_desktop');
    if (resolved.exitCode != 0) {
      stdout.writeln('  FAILED   $manifest could not be generated');
      stdout.writeln(
        '           ${resolved.stderr.toString().trim().split('\n').first}',
      );
      return 1;
    }
    file = File('$repoRoot/$manifest');
    if (!file.existsSync()) {
      stdout.writeln(
        '  FAILED   $manifest still missing after flutter pub get',
      );
      return 1;
    }
  }

  final Map<String, Object?> decoded =
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final Map<String, Object?> plugins =
      decoded['plugins']! as Map<String, Object?>;

  const List<String> desktop = <String>['macos', 'windows', 'linux'];
  final Map<String, Set<String>> covered = <String, Set<String>>{};
  for (final String platform in desktop) {
    for (final Object? entry
        in (plugins[platform] as List<Object?>?) ?? <Object?>[]) {
      String name = (entry! as Map<String, Object?>)['name']! as String;
      for (final String suffix in _federatedSuffixes) {
        if (name.endsWith(suffix)) {
          name = name.substring(0, name.length - suffix.length);
          break;
        }
      }
      covered.putIfAbsent(name, () => <String>{}).add(platform);
    }
  }

  int failed = 0;
  for (final String name in covered.keys.toList()..sort()) {
    final Set<String> missing = desktop.toSet()..removeAll(covered[name]!);
    if (missing.isEmpty) {
      continue;
    }
    final String where = (missing.toList()..sort()).join(', ');
    final String? reason = _acceptedPluginGaps[name];
    if (reason == null) {
      failed++;
      stdout.writeln('  MISSING  $name has no implementation for $where');
      stdout.writeln(
        '           If that is intended, say so in _acceptedPluginGaps.',
      );
    } else {
      stdout.writeln('  known    $name is absent on $where — $reason');
    }
  }

  for (final String name in _acceptedPluginGaps.keys) {
    if (!covered.containsKey(name)) {
      failed++;
      stdout.writeln(
        '  STALE    $name is excused from a gap it no longer has, or is no '
        'longer a dependency at all',
      );
    }
  }
  return failed;
}

// ---------------------------------------------------------------- parsing

_PackageResult _parse(String printed, {required String packageDirectory}) {
  final Map<int, String> suitePaths = <int, String>{};
  final Map<int, int> declaredBySuite = <int, int>{};
  final Map<int, _TestRef> tests = <int, _TestRef>{};
  final Map<int, int> loading = <int, int>{};
  final Map<int, String> errors = <int, String>{};
  final Map<int, String> skipReasons = <int, String>{};
  final Set<int> skipped = <int>{};
  final List<String> failures = <String>[];

  for (final String line in const LineSplitter().convert(printed)) {
    if (!line.startsWith('{')) {
      continue;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, Object?>) {
      continue;
    }
    switch (decoded['type']) {
      case 'suite':
        final Map<String, Object?> suite =
            decoded['suite']! as Map<String, Object?>;
        // `dart test` reports the suite path relative to the package;
        // `flutter test` reports it absolute. The baseline is keyed by path,
        // so it has to be one of the two, forever.
        suitePaths[suite['id']! as int] = _relativeTo(
          suite['path']! as String,
          packageDirectory,
        );
      case 'group':
        final Map<String, Object?> group =
            decoded['group']! as Map<String, Object?>;
        if (group['parentID'] == null) {
          declaredBySuite[group['suiteID']! as int] =
              (group['testCount'] as int?) ?? 0;
        }
      case 'testStart':
        final Map<String, Object?> test =
            decoded['test']! as Map<String, Object?>;
        final String name = test['name']! as String;
        // The runner emits a synthetic "loading <path>" test per suite. It is
        // not a test and must not be counted as one — but when it FAILS the
        // suite did not compile, and dropping it was how a package came back
        // "FAILED, 0 declared" with nothing else printed. Registered apart,
        // so `testDone` can tell a broken test from a suite that never loaded.
        if (name.startsWith('loading ')) {
          loading[test['id']! as int] = test['suiteID']! as int;
          continue;
        }
        tests[test['id']! as int] = _TestRef(
          suiteId: test['suiteID']! as int,
          name: name,
        );
      case 'print':
        if (decoded['messageType'] == 'skip') {
          skipReasons[decoded['testID']! as int] = _normalizeReason(
            decoded['message']! as String,
          );
        }
      case 'error':
        // O texto do erro, guardado pelo id do teste, para o `testDone` poder
        // dizer POR QUE a suite nao carregou em vez de so que nao carregou.
        final int? id = decoded['testID'] as int?;
        if (id != null) {
          final String text = (decoded['error'] as String?)?.trim() ?? '';
          if (text.isNotEmpty) {
            // A primeira linha de um erro de carga e so o preambulo
            // (`Failed to load "…":`); o que diz o que quebrou vem depois.
            // Guardar so a primeira era imprimir o cabecalho e engolir a
            // causa.
            final List<String> lines = const LineSplitter()
                .convert(text)
                .map((String line) => line.trim())
                .where((String line) => line.isNotEmpty)
                .toList();
            final Iterable<String> said =
                lines.first.startsWith('Failed to load')
                ? lines.skip(1).take(2)
                : lines.take(1);
            errors[id] ??= said.isEmpty ? lines.first : said.join(' · ');
          }
        }
      case 'testDone':
        if (decoded['skipped'] == true) {
          skipped.add(decoded['testID']! as int);
        } else if (decoded['result'] != 'success') {
          final int id = decoded['testID']! as int;
          final _TestRef? ref = tests[id];
          if (ref != null) {
            // Com o MOTIVO. `errors[id]` ja era capturado e so servia ao
            // LOAD FAILED; no ramo comum a asserção era descartada e o portao
            // imprimia so o nome — e a resposta ao "por que" custava uma
            // segunda corrida inteira do pacote, 40s no dovetail_cli.
            final String? why = errors[id];
            failures.add(
              '${suitePaths[ref.suiteId]}: ${ref.name}'
              '${why == null ? '' : ' — $why'}',
            );
          } else if (loading.containsKey(id)) {
            final String where = suitePaths[loading[id]] ?? '(unknown suite)';
            failures.add(
              'LOAD FAILED  $where — ${errors[id] ?? 'the suite did not compile'}',
            );
          }
        }
    }
  }

  final Map<String, _Suite> suites = <String, _Suite>{};
  for (final MapEntry<int, String> suite in suitePaths.entries) {
    suites[suite.value] = _Suite(
      declared: declaredBySuite[suite.key] ?? 0,
      skips: <String, String>{},
    );
  }
  for (final int id in skipped) {
    final _TestRef? ref = tests[id];
    if (ref == null) {
      continue;
    }
    final String? path = suitePaths[ref.suiteId];
    if (path == null) {
      continue;
    }
    suites[path]!.skips[ref.name] =
        skipReasons[id] ?? '(the runner reported no reason)';
  }
  return _PackageResult(suites: suites, failures: failures);
}

/// `test(..., skip: 'why')` arrives as "Skip: why" and `markTestSkipped('why')`
/// as "why". Converting one form to the other is a fix, not a change of
/// meaning, and the baseline should not treat it as one.
///
/// Both inputs are normalized to forward slashes first: the Windows runner
/// reports suite paths with backslashes, and a prefix that does not match
/// leaves the suite keyed by an absolute path that `_isTracked` then refuses.
String _relativeTo(String path, String directory) {
  final String normalized = path.replaceAll('\\', '/');
  final String base = directory.replaceAll('\\', '/');
  final String prefix = base.endsWith('/') ? base : '$base/';
  return normalized.startsWith(prefix)
      ? normalized.substring(prefix.length)
      : normalized;
}

String _normalizeReason(String raw) {
  final String trimmed = raw.trim();
  return trimmed.startsWith('Skip: ') ? trimmed.substring(6).trim() : trimmed;
}

// ---------------------------------------------------------------- plumbing

/// O que a corrida foi, junto com o que ela viu.
///
/// Sem isto o arquivo nao sabe dizer nada sobre si: `dist/verify-run.json`
/// chegou a ter 82 bytes — um pacote, `suites` vazio, sobra de um `--only` —
/// e `bless` era um `cp` cego que teria escrito isso por cima do baseline dos
/// doze pacotes. O arquivo passa a carregar se a corrida foi completa, se ela
/// passou, e de qual commit: as tres perguntas que `bless` precisa fazer.
Map<String, Object?> _runHeader({required bool complete, required bool green}) {
  final String sha = Process.runSync('git', <String>[
    'rev-parse',
    'HEAD',
  ], workingDirectory: repoRoot).stdout.toString().trim();
  return <String, Object?>{
    'complete': complete,
    'green': green,
    'commit': sha.isEmpty ? null : sha,
    'packages_expected': _packages.length,
  };
}

Map<String, Object?> _encode(Map<String, _PackageResult> results) =>
    <String, Object?>{
      'packages': <String, Object?>{
        for (final String package in results.keys.toList()..sort())
          package: <String, Object?>{
            'suites': <String, Object?>{
              for (final String suite
                  in results[package]!.suites.keys.toList()..sort())
                suite: <String, Object?>{
                  'declared': results[package]!.suites[suite]!.declared,
                  'skips': <String, Object?>{
                    for (final String test
                        in results[package]!.suites[suite]!.skips.keys.toList()
                          ..sort())
                      test: results[package]!.suites[suite]!.skips[test],
                  },
                },
            },
          },
      },
    };

Map<String, _PackageResult> _decode(Map<String, Object?> raw) {
  final Map<String, Object?> packages =
      raw['packages']! as Map<String, Object?>;
  return <String, _PackageResult>{
    for (final MapEntry<String, Object?> package in packages.entries)
      package.key: _PackageResult(
        failures: const <String>[],
        suites: <String, _Suite>{
          for (final MapEntry<String, Object?> suite
              in ((package.value! as Map<String, Object?>)['suites']!
                      as Map<String, Object?>)
                  .entries)
            suite.key: _Suite(
              declared:
                  (suite.value! as Map<String, Object?>)['declared']! as int,
              skips: <String, String>{
                for (final MapEntry<String, Object?> skip
                    in ((suite.value! as Map<String, Object?>)['skips']!
                            as Map<String, Object?>)
                        .entries)
                  skip.key: skip.value! as String,
              },
            ),
        },
      ),
  };
}

_Run _readRun() {
  final File file = File('$repoRoot/$_runFile');
  if (!file.existsSync()) {
    stderr.writeln('no $_runFile. Run: dart tool/verify.dart test');
    exit(1);
  }
  return _Run(
    results: _decode(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    ),
    failed: false,
  );
}

String _findRepoRoot() {
  Directory here = Directory(
    Platform.environment['DOVETAIL_REPO_ROOT'] ?? Directory.current.path,
  ).absolute;
  for (int step = 0; step < 8; step++) {
    if (Directory('${here.path}/toolkit').existsSync() &&
        Directory('${here.path}/product').existsSync()) {
      return here.path;
    }
    final Directory parent = here.parent;
    if (parent.path == here.path) {
      break;
    }
    here = parent;
  }
  stderr.writeln('no repository root above ${Directory.current.path}');
  exit(1);
}

String? _which(String tool) {
  // `which` does not exist in a cmd shell; `where` is its Windows twin. A
  // gate that reports every tool MISSING on the one system it most needs to
  // run on is a gate that never runs there.
  final ProcessResult found = Process.runSync(
    Platform.isWindows ? 'where' : 'which',
    <String>[tool],
  );
  return found.exitCode == 0 ? found.stdout.toString().trim() : null;
}

String _git(List<String> arguments) => Process.runSync(
  'git',
  arguments,
  workingDirectory: repoRoot,
).stdout.toString();

/// Tudo o que o git rastreia, lido de uma vez.
///
/// Era um `git ls-files --error-unmatch <path>` por chamada, e a chamada e por
/// SUITE: com 127 suites isso sao 127 processos por corrida de `test`, cada um
/// pagando o custo de subir o git e abrir o indice para responder uma pergunta
/// de um bit. Uma leitura so responde todas.
late final Set<String> _trackedFiles = <String>{
  // `-z` separa por NUL. Sem ela o git CITA caminhos com caractere especial
  // (vira `"a\tb"`), e o nome citado nunca casaria com o caminho real: o
  // arquivo passaria por nao-rastreado. O NUL entra como escape, nunca como
  // byte cru no fonte — um byte NUL num arquivo de texto ja cegou um grep
  // neste repositorio uma vez, e o invariante ficou sem ver o arquivo que o
  // violava.
  ...Process.runSync(
    'git',
    <String>['ls-files', '-z'],
    workingDirectory: repoRoot,
  ).stdout.toString().split('\u0000').where((String path) => path.isNotEmpty),
};

bool _isTracked(String path) => _trackedFiles.contains(path);

/// The diff `diff -rq` used to run, done in Dart so it runs on Windows too.
/// Returns the same shape of complaints: files only in one side, and files
/// whose bytes differ.
List<String> _driftBetween(String first, String second) {
  final Map<String, List<int>> left = _readTree(first);
  final Map<String, List<int>> right = _readTree(second);
  final List<String> drift = <String>[];

  final List<String> all = <String>{...left.keys, ...right.keys}.toList()
    ..sort();
  for (final String path in all) {
    final List<int>? a = left[path];
    final List<int>? b = right[path];
    if (a == null) {
      drift.add('only in the second copy: $path');
    } else if (b == null) {
      drift.add('only in the first copy: $path');
    } else if (!_sameBytes(a, b)) {
      drift.add('differs: $path');
    }
  }
  return drift;
}

Map<String, List<int>> _readTree(String root) {
  final Map<String, List<int>> files = <String, List<int>>{};
  void walk(Directory directory, String prefix) {
    for (final FileSystemEntity entity in directory.listSync()) {
      final String name = entity.uri.pathSegments.last;
      final String path = prefix.isEmpty ? name : '$prefix/$name';
      if (entity is Directory) {
        walk(entity, path);
      } else if (entity is File) {
        files[path] = entity.readAsBytesSync();
      }
    }
  }

  walk(Directory(root), '');
  return files;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

final class _TestRef {
  const _TestRef({required this.suiteId, required this.name});
  final int suiteId;
  final String name;
}

final class _Suite {
  const _Suite({required this.declared, required this.skips});
  final int declared;
  final Map<String, String> skips;
}

final class _PackageResult {
  const _PackageResult({required this.suites, required this.failures});
  final Map<String, _Suite> suites;
  final List<String> failures;
}

final class _Outcome {
  const _Outcome({
    required this.package,
    required this.result,
    required this.failed,
    required this.report,
  });
  final String package;
  final _PackageResult result;
  final bool failed;
  final List<String> report;
}

final class _Run {
  const _Run({required this.results, required this.failed});
  final Map<String, _PackageResult> results;
  final bool failed;
}
