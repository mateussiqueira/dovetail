# dovetail_http_client

A typed HTTP client for a product's own API, plus where the token lives. Rust
crate, consumed by the app — not by the privileged component.

It answers two questions: **how a typed call is made** (verbs, retry with
backoff, token refresh on 401, multipart, raw bytes, route redaction for logs)
and **where the access token is kept** (a `TokenStore` trait and a keyring
implementation for the three desktops).

## The line this crate draws

It decides **how the call happens**. It does not decide **what is called**.

| Stays here (generic) | Stays with the app (vocabulary) |
| --- | --- |
| the verbs and their typed bodies | the routes |
| retry policy and exponential backoff | which statuses are retryable *for the product* |
| refresh on 401, serialized by a lock | the refresh route and what it returns |
| `TokenStore` and the keyring adapter | the service name and the entry names |
| route redaction for logs | the route shapes themselves |
| list-envelope normalization | the product's own envelope keys |
| `ApiError` with the HTTP shapes | the code-to-domain-error translation |

The app supplies the refresh as a `TokenRefresher`; the crate never names an
endpoint. `ApiClient::new(config, token_store, refresher)` takes all three.

## The list normalizer — it stays, and this is why

The legacy API answers a collection in more than one shape: a bare array, a
`[items, count]` tuple, or an object under a key. `extract_list_envelope` absorbs
all of them, so the caller does not branch per route.

It is here, and not with the app, because **the mechanism is generic**: any
client over a long-lived API accumulates those shapes. What is not generic is
the *name of the keys* — `emails` and `warnings` are this product's. So the
crate ships the generic keys (`data`, `items`, `results`, `rows`) and the app
passes its own through `extract_list_envelope_with_keys(value, &["emails"])`.

Putting the product's keys in the crate would be the crate learning the
vocabulary it is supposed to not know.

## Route redaction is security, not cosmetics

`redact_route` turns a URL into something safe to log: it keeps the host and the
shape of the path and replaces anything that looks like a value (a long segment,
an e-mail, an all-digit segment, a query string) with `:x`. Confirmation codes,
user ids and tokens that travel in the path never reach a log line.

Every app that logs a request needs this and most write it worse. It is here.

## The keyring, and what it does not assume

`KeyringTokenStore` and `KeyringSessionStore` wrap the `keyring` crate with the
native backend per platform: **Keychain** on macOS, **Credential Manager** on
Windows, **Secret Service** on Linux. The service name and the entry names are
arguments — the crate never hardcodes a product's identifiers.

What differs per platform, and is the app's to handle:

| Platform | Behaviour that is not the crate's |
| --- | --- |
| macOS | the Keychain grants access **per binary**; an ad-hoc signed build changes hash on every rebuild and the prompt returns. A dev flow may need to clear the item before each run. A release build re-signed with a stable identity does not. |
| Windows | the Credential Manager scopes entries to the user account; a service running as another account does not see them. |
| Linux | Secret Service is a D-Bus service. On a headless box it may not exist at all — the failure arrives as `ApiError::TokenStore` carrying the backend message, never as a silent `None`. |

The crate does not paper over any of it: an unavailable backend is an error, not
an empty token. That distinction matters — "no token stored" and "could not read
the store" are different states for a session.

## Consuming it

By **tag**, never by branch. A branch that gets merged and deleted leaves the
dependency pointing at nothing, and only a clean clone finds out.

```toml
dovetail_http_client = { git = "https://github.com/mateussiqueira/dovetail", tag = "v0.1.7" }
```

## What is not here

- the routes and their request/response types;
- the refresh endpoint — the crate calls the `TokenRefresher` the app gives it;
- the product's envelope keys;
- the translation from an HTTP status to a domain error the UI understands;
- anything about the privileged component: see `dovetail_privileged_channel`.
