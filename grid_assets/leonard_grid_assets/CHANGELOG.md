# Changelog

## Unreleased

- Add a typed live-device E2E service, one JSON-emitting `e2e` Command, the
  four-scenario sample-app composition, and the four-step `leonard-e2e`
  circuit to the existing pack registry and manifest.
- Pin the stable schema-aware Leonard agent and CLI wave that carries the
  device tool-schema handshake fix from lenny#123.
- Pin Leonard's packaged operating guide on every E2E driver invocation so a
  dependency-launched CLI never drives from a goal-only prompt.
- Allow a sample-suite invocation to select one named scenario while preserving
  the default four-scenario order and refusing invalid selectors before launch.
- Preserve Leonard CLI's raw VM attachment probe beside each trajectory without
  changing the typed inspector's verdict authority.
- Document the required `leonard_agent` 0.3.1 and `leonard_cli` 0.3.0 pairing.
  Device probing confirmed app registration and VM attachment were already
  healthy; the agent correction losslessly normalizes qwen-mlx's
  schema-declared numeric strings before unchanged strict action validation.

## 0.1.0-rc.2

- Fixed: `interpretEvent` names `SessionOrphaned` in its `RuntimeEvent` switch (lenny#88, lenny-cakq), so the package compiles against every grid_runtime release that carries the SessionOrphaned variant (tg-8kye, the_grid#290); 0.1.0-rc.1 fails to load under any consumer that resolves the current grid_runtime ("The type 'RuntimeEvent' is not exhaustively matched"), which is what blocked lunar_station-luj.
- Floors `grid_runtime` to `^0.2.0-rc.15`, `grid_engine` to `^0.3.0-rc.21` and `grid_sdk` to `^0.3.0-rc.18` — the current the_grid rc wave (14).

## 0.1.0-rc.1

First release — Lenny's grid assets: the station-driven `selfdrive` circuit
(panel-harness daemon, outer driver, receipt verify) and its capability
registry, composable into any the_grid station over `grid_assets`.
