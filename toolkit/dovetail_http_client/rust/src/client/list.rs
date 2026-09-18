use super::*;
use serde::de::DeserializeOwned;

pub const DEFAULT_LIST_KEYS: &[&str] = &["data", "items", "results", "rows"];

impl ApiClient {
    pub async fn get_list<R>(&self, path: &str) -> Result<Vec<R>, ApiError>
    where
        R: DeserializeOwned,
    {
        let value: serde_json::Value = self.get(path).await?;
        let items = extract_list_envelope(value);
        serde_json::from_value(serde_json::Value::Array(items))
            .map_err(|e| ApiError::Internal(format!("failed to type list from {path}: {e}")))
    }
}

pub fn extract_list_envelope(value: serde_json::Value) -> Vec<serde_json::Value> {
    extract_list_envelope_with_keys(value, &[])
}

pub fn extract_list_envelope_with_keys(
    value: serde_json::Value,
    extra_keys: &[&str],
) -> Vec<serde_json::Value> {
    use serde_json::Value;
    match value {
        Value::Array(arr) => match arr.first() {
            Some(Value::Array(_)) => match arr.into_iter().next() {
                Some(Value::Array(items)) => items,
                _ => Vec::new(),
            },
            None => Vec::new(),
            _ => arr,
        },
        Value::Object(mut o) => {
            for key in extra_keys
                .iter()
                .copied()
                .chain(DEFAULT_LIST_KEYS.iter().copied())
            {
                if let Some(Value::Array(items)) = o.remove(key) {
                    return items;
                }
            }
            Vec::new()
        }
        _ => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::{extract_list_envelope, extract_list_envelope_with_keys};
    use serde_json::json;

    #[test]
    fn a_bare_array_is_returned_as_is() {
        let v = json!([{"id":"a"},{"id":"b"}]);
        assert_eq!(extract_list_envelope(v).len(), 2);
    }

    #[test]
    fn a_find_and_count_tuple_is_unwrapped() {
        let v = json!([[{"id":"a"},{"id":"b"},{"id":"c"}], 39]);
        assert_eq!(extract_list_envelope(v).len(), 3);
    }

    #[test]
    fn a_data_envelope_is_unwrapped() {
        let v = json!({"data":[{"id":"a"}]});
        assert_eq!(extract_list_envelope(v).len(), 1);
    }

    #[test]
    fn an_items_envelope_is_unwrapped() {
        let v = json!({"items":[{"id":"a"}]});
        assert_eq!(extract_list_envelope(v).len(), 1);
    }

    #[test]
    fn an_empty_array_is_an_empty_list() {
        assert!(extract_list_envelope(json!([])).is_empty());
    }

    #[test]
    fn an_unknown_shape_is_an_empty_list() {
        assert!(extract_list_envelope(json!({"foo":"bar"})).is_empty());
        assert!(extract_list_envelope(json!("nothing")).is_empty());
        assert!(extract_list_envelope(json!(42)).is_empty());
    }

    #[test]
    fn the_caller_keys_are_tried_before_the_defaults() {
        let v = json!({"otps":[{"id":"a"}], "data":[{"id":"b"}]});
        let items = extract_list_envelope_with_keys(v, &["otps"]);
        assert_eq!(items.len(), 1);
        assert_eq!(items[0]["id"], "a");
    }

    #[test]
    fn the_caller_key_is_only_matched_when_present() {
        let v = json!({"data":[{"id":"b"}]});
        let items = extract_list_envelope_with_keys(v, &["otps"]);
        assert_eq!(items.len(), 1);
        assert_eq!(items[0]["id"], "b");
    }
}
