use global_hotkey::Error;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(i32)]
pub enum Status {
    Ok = 0,
    MalformedChord = 1,
    TakenBySystem = 2,
    AlreadyBound = 3,
    NotBound = 4,
    BackendUnavailable = 5,
}

impl Status {
    pub fn for_registration(error: &Error) -> Self {
        match error {
            Error::AlreadyRegistered(_) => Status::AlreadyBound,
            Error::FailedToRegister(_) => Status::TakenBySystem,
            Error::OsError(_) | Error::FailedToWatchMediaKeyEvent => Status::BackendUnavailable,
            Error::HotKeyParseError(_)
            | Error::UnrecognizedHotKeyCode(_)
            | Error::EmptyHotKeyToken(_)
            | Error::UnexpectedHotKeyFormat(_) => Status::MalformedChord,
            _ => Status::BackendUnavailable,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Error as IoError;

    #[test]
    fn a_refused_combination_should_ask_for_another_key() {
        assert_eq!(
            Status::for_registration(&Error::FailedToRegister(
                "hotkey is reserved by the system".into()
            )),
            Status::TakenBySystem
        );
    }

    #[test]
    fn an_absent_backend_should_not_read_as_a_busy_key() {
        assert_eq!(
            Status::for_registration(&Error::OsError(IoError::other("no display server"))),
            Status::BackendUnavailable,
            "telling a Wayland user to pick another key sends them around a \
             loop no key escapes"
        );
        assert_eq!(
            Status::for_registration(&Error::FailedToWatchMediaKeyEvent),
            Status::BackendUnavailable
        );
    }

    #[test]
    fn a_key_the_manager_already_holds_should_say_so() {
        let hotkey = crate::parse("Ctrl+Shift+V").expect("a valid chord");
        assert_eq!(
            Status::for_registration(&Error::AlreadyRegistered(hotkey)),
            Status::AlreadyBound
        );
    }

    #[test]
    fn a_chord_the_crate_cannot_read_should_be_malformed() {
        for error in [
            Error::HotKeyParseError("bad".into()),
            Error::UnrecognizedHotKeyCode("Frobnicate".into()),
            Error::EmptyHotKeyToken("Ctrl++A".into()),
            Error::UnexpectedHotKeyFormat("A+Ctrl".into()),
        ] {
            assert_eq!(
                Status::for_registration(&error),
                Status::MalformedChord,
                "{error:?}"
            );
        }
    }

    #[test]
    fn every_status_should_keep_the_number_the_dart_side_reads() {
        assert_eq!(Status::Ok as i32, 0);
        assert_eq!(Status::MalformedChord as i32, 1);
        assert_eq!(Status::TakenBySystem as i32, 2);
        assert_eq!(Status::AlreadyBound as i32, 3);
        assert_eq!(Status::NotBound as i32, 4);
        assert_eq!(Status::BackendUnavailable as i32, 5);
    }
}
