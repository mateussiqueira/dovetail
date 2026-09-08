import 'package:{{name}}/main/di/home_module.dart';
import 'package:weave_di/weave_di.dart';

/// A composição inteira do app, num lugar só.
///
/// Cada feature é um escopo que resolve para cima. A ordem de instalação
/// importa: quem exporta entra antes de quem consome — é o que os `imports`
/// de cada módulo declaram, e este grafo só liga as pontas.
WeaveModule rootModule() {
  return WeaveModule(name: 'root', imports: <WeaveModule>[homeModule()]);
}
