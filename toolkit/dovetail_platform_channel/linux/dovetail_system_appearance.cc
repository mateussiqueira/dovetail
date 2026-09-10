#include <gio/gio.h>

#include "dovetail_system_appearance.h"

// A aparencia no Linux nao tem UMA fonte, e as duas que existem discordam de
// proposito.
//
// 1. O **portal XDG** (`org.freedesktop.appearance`/`color-scheme`) e o padrao
//    freedesktop: vale em GNOME, KDE, sway, e dentro de Flatpak, onde o app
//    nem alcanca o dconf do usuario. E o unico que tem o valor `no preference`
//    escrito na especificacao — que e a resposta que este pacote existe para
//    nao perder;
// 2. O **GSettings** (`org.gnome.desktop.interface`/`color-scheme`) responde
//    numa sessao GNOME sem portal rodando.
//
// Nesta ordem, e nao na inversa: o portal e o que vale dentro do sandbox, e um
// app em Flatpak que perguntasse ao dconf primeiro leria o dconf do sandbox,
// que esta vazio, e concluiria "sem preferencia" com o portal ao lado sabendo
// a resposta.
//
// **Os numeros do portal sao invertidos em relacao aos deste header**, e isso
// ja seria um bug se fosse copiado sem olhar: no portal `1` e ESCURO e `2` e
// CLARO; aqui `1` e claro e `2` e escuro. A traducao e explicita logo abaixo.

namespace {

constexpr uint32_t kPortalNoPreference = 0;
constexpr uint32_t kPortalPreferDark = 1;
constexpr uint32_t kPortalPreferLight = 2;

int32_t FromPortalValue(uint32_t value) {
  switch (value) {
    case kPortalPreferDark:
      return DovetailAppearanceDark;
    case kPortalPreferLight:
      return DovetailAppearanceLight;
    case kPortalNoPreference:
    default:
      return DovetailAppearanceUnknown;
  }
}

// O portal responde `Read` como `(v)`, e a variante de dentro carrega o `u`.
// Sao DOIS desembrulhos, e errar isso devolve um GVariant de tipo errado em
// vez de um numero — motivo pelo qual o tipo e conferido antes de ler.
int32_t ReadFromPortal() {
  GError* error = nullptr;
  GDBusProxy* proxy = g_dbus_proxy_new_for_bus_sync(
      G_BUS_TYPE_SESSION, G_DBUS_PROXY_FLAGS_NONE, nullptr,
      "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
      "org.freedesktop.portal.Settings", nullptr, &error);
  if (proxy == nullptr) {
    g_clear_error(&error);
    return DovetailAppearanceUnknown;
  }

  GVariant* reply = g_dbus_proxy_call_sync(
      proxy, "Read",
      g_variant_new("(ss)", "org.freedesktop.appearance", "color-scheme"),
      G_DBUS_CALL_FLAGS_NONE, /*timeout_msec=*/1000, nullptr, &error);
  g_object_unref(proxy);
  if (reply == nullptr) {
    g_clear_error(&error);
    return DovetailAppearanceUnknown;
  }

  GVariant* boxed = nullptr;
  g_variant_get(reply, "(v)", &boxed);
  g_variant_unref(reply);
  if (boxed == nullptr) {
    return DovetailAppearanceUnknown;
  }

  int32_t answer = DovetailAppearanceUnknown;
  if (g_variant_is_of_type(boxed, G_VARIANT_TYPE_UINT32)) {
    answer = FromPortalValue(g_variant_get_uint32(boxed));
  }
  g_variant_unref(boxed);
  return answer;
}

// `g_settings_new` ABORTA o processo quando o schema nao esta instalado — nao
// devolve erro, nao devolve nulo: chama `g_error`. Numa distribuicao sem o
// schema do GNOME isso derrubaria o app inteiro para responder uma pergunta
// sobre cor. Por isso a fonte de schemas e consultada antes.
int32_t ReadFromGSettings() {
  GSettingsSchemaSource* source = g_settings_schema_source_get_default();
  if (source == nullptr) {
    return DovetailAppearanceUnknown;
  }

  GSettingsSchema* schema = g_settings_schema_source_lookup(
      source, "org.gnome.desktop.interface", TRUE);
  if (schema == nullptr) {
    return DovetailAppearanceUnknown;
  }

  // A chave so existe a partir do GNOME 42. Perguntar por uma chave ausente
  // tambem aborta, entao ela e conferida no schema, e nao no valor.
  if (!g_settings_schema_has_key(schema, "color-scheme")) {
    g_settings_schema_unref(schema);
    return DovetailAppearanceUnknown;
  }

  GSettings* settings = g_settings_new_full(schema, nullptr, nullptr);
  g_settings_schema_unref(schema);
  if (settings == nullptr) {
    return DovetailAppearanceUnknown;
  }

  gchar* value = g_settings_get_string(settings, "color-scheme");
  g_object_unref(settings);
  if (value == nullptr) {
    return DovetailAppearanceUnknown;
  }

  int32_t answer = DovetailAppearanceUnknown;
  if (g_strcmp0(value, "prefer-dark") == 0) {
    answer = DovetailAppearanceDark;
  } else if (g_strcmp0(value, "prefer-light") == 0) {
    answer = DovetailAppearanceLight;
  }
  g_free(value);
  return answer;
}

}  // namespace

int32_t DovetailSystemAppearance(void) {
  const int32_t portal = ReadFromPortal();
  if (portal != DovetailAppearanceUnknown) {
    return portal;
  }
  return ReadFromGSettings();
}
