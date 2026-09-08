#!/bin/bash
# Tipo NOVO tem nome em ingles. O historico misto do repositorio fica como esta.
source "$(dirname "${BASH_SOURCE[0]}")/_escopo.sh"
V=0
echo "🔍 Verificando nomes de tipo em linhas novas..."
SUFIXO='(acao|coes|encia|ancia|dade|mento|agem|ismo|orio|aria)'
PALAVRA='(Motor|Fase|Medicao|Ambiente|Sessao|Conta|Carregar|Renovar|Estado|Erro|Servidor|Usuario|Senha|Chave|Arquivo|Pasta|Tempo|Contador|Marca|Janela|Tela|Botao|Lista|Cliente|Pedido|Registro|Resposta|Chamada|Fila|Tarefa|Rede|Conexao|Desfecho|Prova|Camada|Regra)'
while IFS= read -r m; do
  [ -z "$m" ] && continue
  f="${m%%:*}"; r="${m#*:}"; n="${r%%:*}"; c="${r#*:}"
  echo "$c" | grep -qE '^[[:space:]]*(pub[[:space:]]+)?(struct|enum|trait|type)[[:space:]]+[A-Z]' || continue
  nome=$(echo "$c" | sed -E 's/.*(struct|enum|trait|type)[[:space:]]+([A-Z][A-Za-z0-9_]*).*/\2/')
  if echo "$nome" | grep -qiE "$SUFIXO$" || echo "$nome" | grep -qE "^$PALAVRA([A-Z]|$)"; then
    echo "❌ $f:$n — $nome"; V=$((V+1))
  fi
done < <(linhas_novas "rs")
[ "$V" -gt 0 ] && { echo; echo "🚨 $V tipo(s) novo(s) com nome em portugues"; echo "💡 Dica: LoadAccount, nao CarregarConta"; exit 1; }
echo "✅ Tipos novos em ingles"; exit 0
