import 'package:{{name}}/src/rust/frb_generated.dart';
import 'package:dovetail_rust_core/dovetail_rust_core.dart';

/// A fachada do plugin: inicializa a ponte e responde se este host a suporta.
abstract final class {{camel_name}} {
  static final RustBridge instance = RustBridge(initializer: RustLib.init);

  static bool get isSupported => instance.isSupported;

  static Future<void> ensureInitialized() => instance.ensureInitialized();
}
