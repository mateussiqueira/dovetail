import 'package:{{name}}/main/di/home_module.dart';
import 'package:weave_di/weave_di.dart';

WeaveModule rootModule() {
  return WeaveModule(name: 'root', imports: <WeaveModule>[homeModule()]);
}
