use std::str::FromStr;

use global_hotkey::hotkey::HotKey;

pub fn parse(accelerator: &str) -> Result<HotKey, String> {
    let trimmed = accelerator.trim();
    if trimmed.is_empty() {
        return Err("the accelerator is empty".to_owned());
    }
    HotKey::from_str(trimmed).map_err(|error| format!("{trimmed}: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn should_read_the_accelerator_syntax_the_installed_park_already_uses() {
        assert!(parse("Control+Shift+KeyV").is_ok());
        assert!(parse("CommandOrControl+KeyK").is_ok());
        assert!(parse("Alt+F4").is_ok());
    }

    #[test]
    fn should_refuse_an_empty_accelerator() {
        assert!(parse("   ").is_err());
    }

    #[test]
    fn should_refuse_a_key_that_does_not_exist() {
        assert!(parse("Control+KeyNotAKey").is_err());
    }

    #[test]
    fn the_same_chord_should_always_carry_the_same_id() {
        assert_eq!(
            parse("Control+Shift+KeyV").unwrap().id(),
            parse("Control+Shift+KeyV").unwrap().id()
        );
    }

    #[test]
    fn a_different_chord_should_carry_a_different_id() {
        assert_ne!(
            parse("Control+Shift+KeyV").unwrap().id(),
            parse("Control+Shift+KeyB").unwrap().id()
        );
    }

    #[test]
    fn the_order_of_the_modifiers_should_not_change_the_identity() {
        assert_eq!(
            parse("Control+Shift+KeyV").unwrap().id(),
            parse("Shift+Control+KeyV").unwrap().id()
        );
    }

    #[test]
    fn whitespace_around_the_accelerator_should_not_change_it() {
        assert_eq!(
            parse("  Control+KeyV  ").unwrap().id(),
            parse("Control+KeyV").unwrap().id()
        );
    }
}
