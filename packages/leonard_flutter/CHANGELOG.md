# Changelog

## 0.1.1

- Fix: ship the compiled DevTools extension bundle in the published package.
  0.1.0 omitted `extension/devtools/build/` because the repo-root `build/`
  `.gitignore` rule excluded it (`pub publish` honors `.gitignore`), so the
  "Leonard" DevTools tab was missing for consumers. The bundle is now
  un-ignored and shipped.

## 0.1.0

- Host `WidgetsBinding` (`LeonardBinding`) with a single-path perception
  observation pipeline (`PerceptionOwner`-backed serialization).
- `LeonardExtension` authoring contract; core fragment is perception-native.
- Ships the DevTools extension (the "Leonard" tab) via `extension/devtools/`.
- VM-service surface `ext.exploration.*` (protocol-stable).
