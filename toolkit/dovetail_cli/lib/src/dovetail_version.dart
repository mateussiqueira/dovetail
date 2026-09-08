final class DovetailVersion {
  const DovetailVersion._();

  static const String number = '0.1.0';

  static String get line =>
      'dovetail $number ($_os-$_arch, dart $_dart, commit $_commit)';

  static String get targetOs => _os;
  static String get targetArch => _arch;
  static String get dartVersion => _dart;

  static const String _os = String.fromEnvironment(
    'dovetail.os',
    defaultValue: 'unknown',
  );
  static const String _arch = String.fromEnvironment(
    'dovetail.arch',
    defaultValue: 'unknown',
  );

  /// O commit de que este binário saiu. Sem ele, um `dovetail` instalado que
  /// sabe 10 comandos e a árvore que sabe 19 respondem a MESMA linha de
  /// `--version` (o semver está parado em 0.1.0): o único sinal de que o
  /// binário envelheceu é um comando não existir. Vem de `build_release.sh`;
  /// `dart run` não tem, e diz isso.
  static const String _commit = String.fromEnvironment(
    'dovetail.commit',
    defaultValue: 'source',
  );

  static const String _dart = String.fromEnvironment(
    'dovetail.dart',
    defaultValue: 'unknown',
  );

  /// A chave pública que assina o tarball do SDK, embutida pelo
  /// `build_release.sh` — o self-install/self-update verificam a assinatura
  /// do canal contra ela. Vazia num binário de dev, que não passa por essa
  /// esteira.
  static const String sdkReleaseKeyBase64 = String.fromEnvironment(
    'dovetail.sdk_pubkey',
    defaultValue: '',
  );
}
