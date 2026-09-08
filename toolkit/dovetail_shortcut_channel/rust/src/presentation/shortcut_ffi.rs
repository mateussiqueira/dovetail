//! A superficie que o Dart chama: `extern "C"` e nada mais.
//!
//! E a camada de apresentacao desta crate — o nome vem do padrao dos
//! projetos de optimas, e o papel e o mesmo: traduzir o que vem de fora
//! para o vocabulario de dentro, e devolver codigo de status. Nenhuma
//! regra mora aqui.
use crate::domain::status::Status;
use crate::infra::event_pump;
use crate::infra::hotkey_parser;

use std::ffi::{c_char, CStr, CString};
use std::ptr;
use std::sync::Mutex;

use global_hotkey::hotkey::HotKey;
use global_hotkey::GlobalHotKeyManager;

static LAST_OPEN_FAILURE: Mutex<Option<CString>> = Mutex::new(None);

fn remember_open_failure(reason: String) {
    let encoded = CString::new(reason).unwrap_or_else(|_| {
        CString::new("the platform reported a reason that is not text")
            .expect("literal holds no interior nul")
    });
    *LAST_OPEN_FAILURE
        .lock()
        .expect("open failure lock poisoned") = Some(encoded);
}

pub struct Registry {
    manager: GlobalHotKeyManager,
    bound: Mutex<Vec<HotKey>>,
    failure: Mutex<Option<CString>>,
}

impl Registry {
    fn open() -> Result<Self, String> {
        let backend = crate::infra::backend_probe::detect();
        if !backend.registers() {
            return Err(backend.cannot_register());
        }

        GlobalHotKeyManager::new()
            .map(|manager| Registry {
                manager,
                bound: Mutex::new(Vec::new()),
                failure: Mutex::new(None),
            })
            .map_err(|error| error.to_string())
    }

    fn remember(&self, reason: String) {
        let encoded = CString::new(reason).unwrap_or_else(|_| {
            CString::new("the platform reported a reason that is not text")
                .expect("literal holds no interior nul")
        });
        *self.failure.lock().expect("failure lock poisoned") = Some(encoded);
    }

    fn bind(&self, accelerator: &str) -> Result<u32, Status> {
        let hotkey = hotkey_parser::parse(accelerator).map_err(|reason| {
            self.remember(reason);
            Status::MalformedChord
        })?;

        if self
            .bound
            .lock()
            .expect("bound lock poisoned")
            .iter()
            .any(|known| known.id() == hotkey.id())
        {
            self.remember(format!("{accelerator} is already bound by this app"));
            return Err(Status::AlreadyBound);
        }

        self.manager.register(hotkey).map_err(|error| {
            let status = Status::for_registration(&error);
            self.remember(error.to_string());
            status
        })?;

        self.bound.lock().expect("bound lock poisoned").push(hotkey);
        Ok(hotkey.id())
    }

    fn release(&self, id: u32) -> Status {
        let mut bound = self.bound.lock().expect("bound lock poisoned");
        let Some(index) = bound.iter().position(|known| known.id() == id) else {
            return Status::NotBound;
        };
        let hotkey = bound.remove(index);
        drop(bound);

        match self.manager.unregister(hotkey) {
            Ok(()) => Status::Ok,
            Err(error) => {
                self.remember(error.to_string());
                Status::BackendUnavailable
            }
        }
    }

    fn release_all(&self) -> Status {
        let ids: Vec<u32> = self
            .bound
            .lock()
            .expect("bound lock poisoned")
            .iter()
            .map(|hotkey| hotkey.id())
            .collect();

        let mut worst = Status::Ok;
        for id in ids {
            let status = self.release(id);
            if status != Status::Ok {
                worst = status;
            }
        }
        worst
    }
}

#[no_mangle]
pub extern "C" fn dovetail_shortcut_backend() -> i32 {
    crate::infra::backend_probe::detect() as i32
}

#[no_mangle]
pub extern "C" fn dovetail_shortcut_open() -> *mut Registry {
    match Registry::open() {
        Ok(registry) => {
            *LAST_OPEN_FAILURE
                .lock()
                .expect("open failure lock poisoned") = None;
            Box::into_raw(Box::new(registry))
        }
        Err(reason) => {
            remember_open_failure(reason);
            ptr::null_mut()
        }
    }
}

/// # Safety
/// The returned pointer is owned by this library and stays valid until the
/// next failing `dovetail_shortcut_open`.
#[no_mangle]
pub unsafe extern "C" fn dovetail_shortcut_last_open_failure() -> *const c_char {
    match LAST_OPEN_FAILURE
        .lock()
        .expect("open failure lock poisoned")
        .as_ref()
    {
        Some(reason) => reason.as_ptr(),
        None => ptr::null(),
    }
}

/// # Safety
/// `registry` must come from `dovetail_shortcut_open` and not yet be closed.
#[no_mangle]
pub unsafe extern "C" fn dovetail_shortcut_close(registry: *mut Registry) {
    if registry.is_null() {
        return;
    }
    let owned = Box::from_raw(registry);
    owned.release_all();
}

/// # Safety
/// `registry` must be live and `accelerator` a nul-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn dovetail_shortcut_bind(
    registry: *mut Registry,
    accelerator: *const c_char,
    out_id: *mut u32,
) -> i32 {
    let Some(registry) = registry.as_ref() else {
        return Status::BackendUnavailable as i32;
    };
    if accelerator.is_null() || out_id.is_null() {
        return Status::MalformedChord as i32;
    }

    let Ok(text) = CStr::from_ptr(accelerator).to_str() else {
        registry.remember("the accelerator is not valid UTF-8".to_owned());
        return Status::MalformedChord as i32;
    };

    match registry.bind(text) {
        Ok(id) => {
            *out_id = id;
            Status::Ok as i32
        }
        Err(status) => status as i32,
    }
}

/// # Safety
/// `registry` must be live.
#[no_mangle]
pub unsafe extern "C" fn dovetail_shortcut_release(registry: *mut Registry, id: u32) -> i32 {
    match registry.as_ref() {
        Some(registry) => registry.release(id) as i32,
        None => Status::BackendUnavailable as i32,
    }
}

/// # Safety
/// `registry` must be live.
#[no_mangle]
pub unsafe extern "C" fn dovetail_shortcut_release_all(registry: *mut Registry) -> i32 {
    match registry.as_ref() {
        Some(registry) => registry.release_all() as i32,
        None => Status::BackendUnavailable as i32,
    }
}

/// # Safety
/// `registry` must be live. The returned pointer is owned by the registry and
/// stays valid until the next failing call on it.
#[no_mangle]
pub unsafe extern "C" fn dovetail_shortcut_last_failure(registry: *mut Registry) -> *const c_char {
    let Some(registry) = registry.as_ref() else {
        return ptr::null();
    };
    match registry
        .failure
        .lock()
        .expect("failure lock poisoned")
        .as_ref()
    {
        Some(reason) => reason.as_ptr(),
        None => ptr::null(),
    }
}

#[no_mangle]
pub extern "C" fn dovetail_shortcut_listen(callback: Option<event_pump::Listener>) -> i32 {
    event_pump::listen(callback)
}

#[cfg(feature = "test-probe")]
#[no_mangle]
pub extern "C" fn dovetail_shortcut_emit_probe(id: u32, pressed: u8) {
    event_pump::emit_from_own_thread(id, pressed != 0);
}
