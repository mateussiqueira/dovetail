use std::env;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=xpc_shim.c");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }
    let out = env::var("OUT_DIR").expect("OUT_DIR");
    let obj = format!("{out}/xpc_shim.o");
    let lib = format!("{out}/libdovetail_xpc_shim.a");
    let clang = env::var("CLANG").unwrap_or_else(|_| "clang".into());
    run(Command::new(clang).args(["-c", "-fblocks", "-O2", "-fPIC", "xpc_shim.c", "-o", &obj]));
    let _ = std::fs::remove_file(&lib);
    run(Command::new("ar").args(["crs", &lib, &obj]));
    println!("cargo:rustc-link-search=native={out}");
    println!("cargo:rustc-link-lib=static=dovetail_xpc_shim");
}

fn run(cmd: &mut Command) {
    assert!(
        cmd.status().expect("processo do build").success(),
        "comando do build do shim XPC falhou"
    );
}
