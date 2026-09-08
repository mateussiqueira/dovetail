// swift-tools-version: 5.9
import PackageDescription

// O único alvo é um binaryTarget: o dylib do Rust pré-construído pelo
// tool/build_xcframework.sh, embutido no app. Sem código Swift — a ponte
// carrega por dart:ffi. Binary targets não podem declarar dependências;
// mencionar FlutterFramework aqui satisfaz o check do flutter_tools.
let binaryTarget = Target.binaryTarget(
    name: "{{name}}",
    path: "{{name}}.xcframework"
)

let package = Package(
    name: "{{name}}",
    platforms: [.macOS("10.15")],
    products: [.library(name: "{{name}}", targets: ["{{name}}"])],
    targets: [binaryTarget]
)
