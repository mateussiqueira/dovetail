use std::env;
use std::ffi::{c_char, CStr, CString};
use std::ptr;

use dovetail_shortcut_channel::{
    dovetail_shortcut_backend, dovetail_shortcut_bind, dovetail_shortcut_close,
    dovetail_shortcut_last_open_failure, dovetail_shortcut_open,
};

fn shown(name: &str) -> String {
    match env::var(name) {
        Ok(value) if !value.trim().is_empty() => value,
        _ => String::from("(unset)"),
    }
}

fn name_of(code: i32) -> &'static str {
    match code {
        0 => "none",
        1 => "win32RegisterHotKey",
        2 => "carbonEventHotKey",
        3 => "x11GrabKey",
        4 => "waylandPortal",
        _ => "unknown",
    }
}

fn status_of(code: i32) -> &'static str {
    match code {
        0 => "ok",
        1 => "alreadyBound",
        2 => "takenBySystem",
        3 => "backendUnavailable",
        4 => "malformedChord",
        _ => "unknown",
    }
}

fn last_failure() -> String {
    let reason: *const c_char = unsafe { dovetail_shortcut_last_open_failure() };
    if reason.is_null() {
        return String::from("(none reported)");
    }
    unsafe { CStr::from_ptr(reason) }
        .to_string_lossy()
        .into_owned()
}

fn main() {
    for name in [
        "XDG_SESSION_TYPE",
        "WAYLAND_DISPLAY",
        "DISPLAY",
        "XDG_CURRENT_DESKTOP",
    ] {
        println!("env {name}={}", shown(name));
    }

    let code = dovetail_shortcut_backend();
    println!("backend={} ({code})", name_of(code));
    println!(
        "detect_agrees={}",
        code == dovetail_shortcut_channel::detect() as i32
    );

    let registry = dovetail_shortcut_open();
    if registry.is_null() {
        println!("open=refused");
        println!("open_reason={}", last_failure());
        return;
    }
    println!("open=accepted");

    let accelerator =
        CString::new("CommandOrControl+Shift+K").expect("literal holds no interior nul");
    let mut id: u32 = 0;
    let bound =
        unsafe { dovetail_shortcut_bind(registry, accelerator.as_ptr(), ptr::addr_of_mut!(id)) };
    println!("bind={} ({bound})", status_of(bound));
    if bound == 0 {
        println!("bind_id={id}");
    }

    unsafe { dovetail_shortcut_close(registry) };
    println!("closed=yes");
}
