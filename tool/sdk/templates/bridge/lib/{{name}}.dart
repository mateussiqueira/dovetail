/// O barril do plugin. O codegen preenche `lib/src/rust/`; conforme os
/// repasses entram em `rust/src/api/`, exporte cada módulo gerado aqui,
/// como o fixture faz.
// A diretiva existe para o comentário acima ter dono: sem ela o analyzer
// acusa `dangling_library_doc_comments` — e este era o único lint que o
// próprio template entregava a todo projeto gerado, escondido porque o
// analysis_options do app excluía core_bridge/** inteiro.
library;

export 'package:{{name}}/src/bridge.dart';
