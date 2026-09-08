import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';

void main() {
  final RegExp guid = RegExp(
    r'^[0-9A-F]{8}-[0-9A-F]{4}-5[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$',
  );

  test('should be a version 5 GUID, uppercase, as WiX writes them', () {
    expect(UpgradeCode.forIdentifier('com.example.demo'), matches(guid));
  });

  test('should be exactly uuid5(NAMESPACE_URL, "dovetail:<identifier>")', () {
    // Vetor calculado com `uuid.uuid5(uuid.NAMESPACE_URL,
    // 'dovetail:com.example.demo')` do Python. Mudar este valor orfana todo
    // MSI ja instalado: o Windows Installer nao reconheceria o proximo como
    // o mesmo produto e instalaria ao lado.
    expect(
      UpgradeCode.forIdentifier('com.example.demo'),
      'E7AB9275-18C7-5A57-8C3C-BE79348C102C',
    );
  });

  test('the same identifier should always give the same code', () {
    // O Windows Installer usa o UpgradeCode para saber que um MSI novo
    // SUBSTITUI o instalado; um codigo que muda por build instala ao lado.
    expect(
      UpgradeCode.forIdentifier('com.example.demo'),
      UpgradeCode.forIdentifier('com.example.demo'),
    );
  });

  test('two products should never share one', () {
    expect(
      UpgradeCode.forIdentifier('com.example.demo'),
      isNot(UpgradeCode.forIdentifier('com.example.other')),
    );
  });
}
