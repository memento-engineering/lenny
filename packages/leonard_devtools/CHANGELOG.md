# Changelog

## 0.2.0

- Breaking: the DevTools extension probes and consumes `ext.leonard.*`
  extensions (protocol version 2); requires an app on `leonard_agent` 0.2.0.

## 0.1.1

- Provider construction moves to the `DartanticModelProvider` seam (the agent's
  unified backend factory).
- Fix: a run-level provider/HTTP failure no longer crashes the panel. The
  session run future now surfaces a terminal error status instead of escaping
  its `unawaited` wrapper as an unhandled async error (which previously took
  down the whole DevTools extension when, e.g., the model request threw).

## 0.1.0

Initial release.
