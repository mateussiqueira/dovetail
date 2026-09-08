use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::thread;

use global_hotkey::{GlobalHotKeyEvent, HotKeyState};

use crate::domain::status::Status;

pub type Listener = extern "C" fn(u32, u8);

static LISTENER: Mutex<Option<Listener>> = Mutex::new(None);
static PUMPING: AtomicBool = AtomicBool::new(false);

pub fn listen(callback: Option<Listener>) -> i32 {
    *LISTENER.lock().expect("listener lock poisoned") = callback;

    if callback.is_none() || PUMPING.swap(true, Ordering::SeqCst) {
        return Status::Ok as i32;
    }

    thread::Builder::new()
        .name("shortcut-pump".to_owned())
        .spawn(pump)
        .map(|_| Status::Ok as i32)
        .unwrap_or(Status::BackendUnavailable as i32)
}

#[cfg(any(test, feature = "test-probe"))]
pub fn emit_from_own_thread(id: u32, pressed: bool) {
    let handle = thread::Builder::new()
        .name("shortcut-probe".to_owned())
        .spawn(move || emit(id, pressed));
    if let Ok(handle) = handle {
        let _ = handle.join();
    }
}

pub fn emit(id: u32, pressed: bool) {
    let listener = *LISTENER.lock().expect("listener lock poisoned");
    if let Some(callback) = listener {
        callback(id, u8::from(pressed));
    }
}

fn pump() {
    let receiver = GlobalHotKeyEvent::receiver();
    loop {
        match receiver.recv() {
            Ok(event) => emit(event.id, event.state == HotKeyState::Pressed),
            Err(_) => {
                PUMPING.store(false, Ordering::SeqCst);
                return;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicU32;

    static SEEN_ID: AtomicU32 = AtomicU32::new(0);
    static SEEN_PRESSED: AtomicU32 = AtomicU32::new(0);
    static SERIAL: Mutex<()> = Mutex::new(());

    extern "C" fn record(id: u32, pressed: u8) {
        SEEN_ID.store(id, Ordering::SeqCst);
        SEEN_PRESSED.store(u32::from(pressed), Ordering::SeqCst);
    }

    #[test]
    fn a_press_emitted_from_another_thread_should_reach_the_listener() {
        let _serial = SERIAL.lock().expect("serial lock poisoned");
        assert_eq!(listen(Some(record)), Status::Ok as i32);
        SEEN_ID.store(0, Ordering::SeqCst);
        emit_from_own_thread(777, true);
        assert_eq!(SEEN_ID.load(Ordering::SeqCst), 777);
        listen(None);
    }

    #[test]
    fn a_press_should_reach_the_listener_that_is_installed() {
        let _serial = SERIAL.lock().expect("serial lock poisoned");
        assert_eq!(listen(Some(record)), Status::Ok as i32);
        emit(4242, true);
        assert_eq!(SEEN_ID.load(Ordering::SeqCst), 4242);
        assert_eq!(SEEN_PRESSED.load(Ordering::SeqCst), 1);

        emit(4242, false);
        assert_eq!(SEEN_PRESSED.load(Ordering::SeqCst), 0);

        listen(None);
        emit(9999, true);
        assert_eq!(
            SEEN_ID.load(Ordering::SeqCst),
            4242,
            "a released listener must stop receiving"
        );
    }

    #[test]
    fn installing_a_listener_twice_should_not_start_a_second_pump() {
        let _serial = SERIAL.lock().expect("serial lock poisoned");
        assert_eq!(listen(Some(record)), Status::Ok as i32);
        assert_eq!(listen(Some(record)), Status::Ok as i32);
        listen(None);
    }
}
