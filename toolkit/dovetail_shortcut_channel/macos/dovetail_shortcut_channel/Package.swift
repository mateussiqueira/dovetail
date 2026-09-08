// swift-tools-version: 5.9
import PackageDescription

// O único alvo é um binaryTarget: o dylib do Rust pré-construído pelo
// tool/build_xcframework.sh, embutido no app. Sem código Swift — a ponte
// carrega por dart:ffi (DynamicLibrary.open). Binary targets não podem
// declarar dependências; mencionar FlutterFramework aqui satisfaz o check
// do flutter_tools, que avisa quando o manifest não o cita.
let binaryTarget = Target.binaryTarget(
    name: "dovetail_shortcut_channel",
    path: "dovetail_shortcut_channel.xcframework"
)

let package = Package(
    name: "dovetail_shortcut_channel",
    platforms: [.macOS("10.15")],
    products: [.library(name: "desktop-shortcut-channel", targets: ["dovetail_shortcut_channel"])],
    targets: [binaryTarget]
)
