#!/bin/bash
# Verifica convenções de nomenclatura de arquivos e classes.
# Regras:
#   - Models: *_model.dart (classe *Model)
#   - Entities: *_entity.dart (classe *Entity)
#   - Usecases: *_usecase.dart ou nome_da_acao.dart
#   - Pages: *_page.dart (classe *Page)
#   - Widgets: *_widget.dart ou nome_do_widget.dart (classe *Widget)
#   - Presenters: *_presenter.dart (classe *Presenter)
#   - Errors: *_error.dart (classe *Error)
# Uso: ./check_naming_conventions.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando convenções de nomenclatura..."

check_file() {
  local file="$1"
  local pattern="$2"
  local expected_suffix="$3"
  local file_type="$4"
  
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    
    # Ignorar barrel files
    head -1 "$file" 2>/dev/null | grep -qE '^export ' && return
    
    # Verificar se o arquivo termina com o sufixo esperado
    if ! echo "$filename" | grep -qE "$pattern"; then
      echo "❌ $file — $file_type deve terminar com $expected_suffix"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  fi
}

# Verificar Models
for file in $(find "$DIR/data/models" -name "*.dart" -not -path "*/build/*" 2>/dev/null); do
  check_file "$file" '_model\.dart$' '_model.dart' 'Model'
done

# Verificar Entities
for file in $(find "$DIR/domain/entities" -name "*.dart" -not -path "*/build/*" 2>/dev/null); do
  # Ignorar barrel files
  head -1 "$file" 2>/dev/null | grep -qE '^export ' && continue
  check_file "$file" '_entity\.dart$' '_entity.dart' 'Entity'
done

# Verificar Pages
for file in $(find "$DIR/presentation/ui/pages" -name "*.dart" -not -path "*/build/*" 2>/dev/null); do
  check_file "$file" '_page\.dart$' '_page.dart' 'Page'
done

# Verificar Presenters
for file in $(find "$DIR/presentation/presenters" -name "*.dart" -not -path "*/build/*" 2>/dev/null); do
  # Ignorar barrel files
  head -1 "$file" 2>/dev/null | grep -qE '^export ' && continue
  check_file "$file" '_presenter\.dart$' '_presenter.dart' 'Presenter'
done

# Verificar Errors
for file in $(find "$DIR/domain/errors" -name "*.dart" -not -path "*/build/*" 2>/dev/null); do
  check_file "$file" '_error\.dart$' '_error.dart' 'Error'
done

for file in $(find "$DIR/presentation/errors" -name "*.dart" -not -path "*/build/*" 2>/dev/null); do
  check_file "$file" '_error\.dart$' '_error.dart' 'Error'
done

# Verificar Widgets (arquivos na pasta widgets)
for file in $(find "$DIR/presentation/ui/widgets" -name "*.dart" -not -path "*/build/*" 2>/dev/null); do
  # Ignorar barrel files
  head -1 "$file" 2>/dev/null | grep -qE '^export ' && continue
  
  filename=$(basename "$file")
  
  # Widgets podem ter vários padrões: *_widget.dart, *_button.dart, *_card.dart, etc.
  # Mas não podem ter sufixos como _data, _model, _entity, _presenter
  if echo "$filename" | grep -qE '_(data|model|entity|presenter|usecase|error)\.dart$'; then
    echo "❌ $file — widget não pode terminar com _data, _model, _entity, _presenter, _usecase ou _error"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS violação(ões) de nomenclatura detectada(s)"
  echo "💡 Siga as convenções: *_model.dart, *_entity.dart, *_page.dart, *_presenter.dart"
  exit 1
else
  echo "✅ Todas as convenções de nomenclatura estão corretas"
  exit 0
fi
