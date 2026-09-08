import 'package:args/args.dart';
import 'package:args/command_runner.dart';

/// Uma opção obrigatória lida como recusa de uso, e não como defeito.
///
/// `package:args` tem `mandatory: true`, e ele parece a resposta certa — mas
/// não valida na análise: lança `ArgumentError` no momento da LEITURA. Isso
/// escapa do comando, cai no `catch (Object)` do `bin/dovetail.dart`, e o que
/// o usuário vê por ter esquecido `--product-name` é:
///
/// ```
/// dovetail: an unexpected ArgumentError escaped.
///   This is a defect in dovetail, not in your project.
///   #0      ArgResults.option (package:args/src/arg_results.dart:106:7)
///   ...
/// ```
///
/// Três coisas erradas de uma vez. O texto acusa o dovetail de um erro que é
/// de digitação; o usuário recebe nove quadros de pilha de dentro do
/// `package:args` em vez do bloco de uso do comando; e o saída é 1 quando
/// todo o resto da CLI devolve 64 para uso incorreto. De quebra, cada engano
/// desses vira uma entrada no `~/.dovetail/log/dovetail.log`, que existe para
/// o suporte — enchendo de ruído o diário que deveria ter só o que importa.
///
/// Este helper devolve a mesma recusa que o resto da CLI já dá à mão: o
/// `manifest` para `--release` ("at least one --release is needed"), o `sign`
/// para `--bundle` ("macos needs --bundle"). Uma forma só, e nenhuma pilha.
String requiredOption(ArgResults args, String name, String usage) {
  final String? given = args.option(name);
  if (given == null) {
    throw UsageException('--$name is required.', usage);
  }
  return given;
}
