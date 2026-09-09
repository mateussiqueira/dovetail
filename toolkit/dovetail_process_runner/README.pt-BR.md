**Português** · [English](README.md)

# dovetail_process_runner

> Rodar um processo e receber o que ele disse — com um dublê que os testes usam
> no lugar, e sem os três impasses que `Process.run` tem de fábrica.

Metade do que este toolkit faz é chamar ferramenta de outra gente: `codesign`,
`signtool`, `minisign`, `hdiutil`, `dpkg`, `rpmbuild`, `makensis`, `wixl`,
`osslsigncode`, `pkexec`. Um pacote inteiro para isso existe por dois motivos, e
nenhum é elegância.

## O motivo que aparece no teste

`ProcessRunner` é interface. Todo bundler, todo signer e todo installer recebe
uma pelo construtor, então o teste passa um dublê e **prende os argumentos** —
não o resultado de ter rodado a ferramenta, que na máquina de quem lê pode nem
estar instalada.

```dart
final RecordingRunner runner = RecordingRunner();
await DmgBundler(runner: runner).bundle(spec);

expect(runner.arguments, containsAllInOrder(<String>['-volname', 'Exemplo']));
```

É por isso que `dovetail_bundler` prova a linha de comando de `wixl` e de
`rpmbuild` num Mac sem nenhum dos dois. Onde a ferramenta existe, o mesmo teste
roda com `SystemProcessRunner` e confere o arquivo que saiu.

## O motivo que não aparece: três impasses

**O primeiro é a saída que enche o cano.** Um pipe do SO tem uns 64 KB. Se o
processo filho escreve mais que isso e ninguém lê, ele bloqueia na escrita — e
quem espera pelo `exitCode` espera para sempre. Aqui a drenagem de `stdout` e
`stderr` começa **antes** de qualquer coisa ser escrita em `stdin`, e não
depois:

```dart
final Future<void> draining = Future.wait(<Future<void>>[...]);   // primeiro
if (stdin != null) { process.stdin.write(stdin); }                 // depois
```

Três testes prendem isso com saída grande de verdade — em `stdout`, em `stderr`,
e com `stdin` grande junto —, porque a versão que troca essas duas linhas de
lugar passa em todo teste pequeno.

**O segundo é o `stdin` que nunca fecha.** `minisign` espera senha em `stdin` e
não termina enquanto o descritor estiver aberto. `close()` é incondicional, e
não só quando havia algo a escrever.

**O terceiro é o processo que trava.** `timeout` mata com `SIGKILL`, espera o
`exitCode` de verdade, dá uma folga curta para a drenagem terminar, e lança
`ProcessTimeout` carregando **o que o processo tinha dito até ali** — que é
exatamente onde está a pista de por que ele travou.

## O que ele devolve

```dart
final ProcessOutcome outcome = await runner.run('minisign', <String>[
  '-S', '-s', keyPath, artifactPath,
], stdin: '$password\n', timeout: const Duration(seconds: 60));

if (!outcome.succeeded) {
  throw SigningFailure('minisign falhou', remedy: outcome.firstDiagnostic);
}
```

`firstDiagnostic` prefere `stderr`, cai para `stdout` quando ele está em branco,
e quando os dois estão vazios diz o código de saída — em vez de devolver string
vazia como motivo, que é como uma falha vira "algo deu errado".

`toString` reporta o **tamanho** de `stdout` e `stderr`, não o conteúdo: um
`ProcessOutcome` num log de erro não deve despejar dez mil linhas nem, pior,
ecoar o que foi escrito em `stdin`.

## `ProcessLauncher` é outra coisa, de propósito

```dart
final int pid = await launcher.launch('msiexec', <String>['/i', installer]);
```

`run` espera e captura. `launch` **solta o processo e devolve o pid**, em modo
destacado — é o que o instalador do Windows precisa, porque o `.msi` substitui o
executável que está rodando e o app tem de sair antes de ele terminar. Esperar
ali seria esperar por um processo que só termina depois de matar quem espera.

`SystemProcessRunner` implementa as duas interfaces, e quem depende só de uma
declara só aquela.

## O que este package não faz

Não interpreta saída, não conhece ferramenta nenhuma, não decide o que é falha
além do código de saída. `runInShell` é `false` e não é configurável: passar uma
linha por shell é como um caminho com espaço vira dois argumentos, e como um
nome de arquivo vindo de fora vira comando.
