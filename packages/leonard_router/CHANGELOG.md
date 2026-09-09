# Changelog

## 0.4.0

Promotes `0.4.0-rc.1` to stable.

- **Breaking: requires `leonard_flutter ^0.4.0`** (the `captureScreenshot`
  signature wave). Migration: move the `leonard_flutter` constraint to `^0.4.0`
  and drop the `captureScreenshot` argument. No API changes in this package;
  the effective-route reporting shipped in 0.3.1.

## 0.4.0-rc.1

- Require `leonard_flutter ^0.4.0-rc.1` (the `captureScreenshot` signature wave).
  No API changes in this package; the effective-route reporting shipped in
  0.3.1.

## 0.3.1

- Fix: a navigation success result preserves the requested route AND reports the
  observed post-navigation route read from the shared snapshot, so a redirect is
  visible to the driver. `ok` semantics are unchanged.
- Fix: post-navigation frame observation is capped at 250 ms, and results
  distinguish an observed, an unobserved and a timed-out route snapshot.

## 0.3.0

- Breaking: require `leonard_flutter ^0.3.0`; test support now comes from
  `leonard_flutter_test`, and perception serialization is imported directly
  from `genesis_perception`.

## 0.2.1

- Bump `genesis_perception` to `^0.2.0` (the genesis builder wave). No API
  changes in this package; the perception wire contract is unchanged.

## 0.2.0

- Breaking: requires `leonard_flutter` 0.2.0 (the `ext.leonard.*` namespace
  wave). No API changes in this package.

## 0.1.0

Initial release.
