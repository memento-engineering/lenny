/// Lenny's grid assets — the `*_grid_assets` pack for the `lenny` repo.
///
/// Today the package vends the station-driven `selfdrive` circuit, the four
/// capabilities behind it, its bead work-policy resolver, and a registry that
/// composes them over `grid_assets`' code registry. Later Lenny assets are
/// added to this same package rather than creating a second package identity.
library;

export 'src/selfdrive/outer_driver.dart';
export 'src/selfdrive/panel_harness.dart';
export 'src/selfdrive/selfdrive_circuit.dart';
export 'src/selfdrive/selfdrive_preflight.dart';
export 'src/selfdrive/selfdrive_registry.dart';
export 'src/selfdrive/selfdrive_verify.dart';
