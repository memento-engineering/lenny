# Changelog

## Unreleased

- Add a typed live-device E2E service, one JSON-emitting `e2e` Command, the
  four-scenario sample-app composition, and the four-step `leonard-e2e`
  circuit to the existing pack registry and manifest.

## 0.1.0-rc.2

- Fixed: `interpretEvent` names `SessionOrphaned` in its `RuntimeEvent` switch (lenny#88, lenny-cakq), so the package compiles against every grid_runtime release that carries the SessionOrphaned variant (tg-8kye, the_grid#290); 0.1.0-rc.1 fails to load under any consumer that resolves the current grid_runtime ("The type 'RuntimeEvent' is not exhaustively matched"), which is what blocked lunar_station-luj.
- Floors `grid_runtime` to `^0.2.0-rc.15`, `grid_engine` to `^0.3.0-rc.21` and `grid_sdk` to `^0.3.0-rc.18` — the current the_grid rc wave (14).

## 0.1.0-rc.1

First release — Lenny's grid assets: the station-driven `selfdrive` circuit
(panel-harness daemon, outer driver, receipt verify) and its capability
registry, composable into any the_grid station over `grid_assets`.
