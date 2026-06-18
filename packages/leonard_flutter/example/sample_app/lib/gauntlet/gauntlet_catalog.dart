/// Single source of truth for the gauntlet's scenarios, shared by the
/// index screen and the router. Each entry isolates ONE documented
/// failure mode of an observe-then-act agent. `built == false` entries are
/// shown on the index as not-yet-implemented so the full plan is visible
/// without being navigable.
class GauntletScenario {
  const GauntletScenario({
    required this.id,
    required this.lane,
    required this.title,
    required this.trap,
    required this.built,
  });

  /// Stable id without the `/g/` prefix, e.g. `settle/decorative-motion`.
  final String id;

  /// Lane label for grouping on the index.
  final String lane;

  /// Human title shown on the index tile.
  final String title;

  /// One-line description of the trap this scenario sets.
  final String trap;

  /// Whether a screen + route exists yet.
  final bool built;

  /// Full router path.
  String get route => '/g/$id';
}

const String laneSettle = 'A · Settle & timing';
const String laneControls = 'B · Controls & semantics';
const String laneVision = 'C · Hide-n-seek / vision';

/// The catalog. Add a scenario here, build its screen, and register its
/// route in `router.dart` against the same path.
const List<GauntletScenario> gauntletScenarios = <GauntletScenario>[
  // ── Lane A ──────────────────────────────────────────────────────────
  GauntletScenario(
    id: 'settle/decorative-motion',
    lane: laneSettle,
    title: 'Decorative perpetual motion',
    trap:
        'A shimmer that never stops. The settle policy must act anyway, '
        'not wait forever for "no pending frames".',
    built: true,
  ),
  GauntletScenario(
    id: 'settle/async-reveal',
    lane: laneSettle,
    title: 'Async-gated reveal',
    trap:
        'A confirmation code appears only after a network call. Look '
        'early and the screen is empty.',
    built: true,
  ),
  GauntletScenario(
    id: 'settle/optimistic-revert',
    lane: laneSettle,
    title: 'Optimistic-then-reconcile',
    trap:
        'A like fills instantly, then the server reverts it. Report the '
        'settled state, not the flash.',
    built: true,
  ),
  GauntletScenario(
    id: 'settle/debounced-search',
    lane: laneSettle,
    title: 'Debounced search',
    trap:
        'Type → debounce → fetch → results. Three pending stages to wait '
        'through.',
    built: true,
  ),
  GauntletScenario(
    id: 'settle/staggered-list',
    lane: laneSettle,
    title: 'Staggered list entrance',
    trap: 'Twenty items animate in over a second. Count after they land.',
    built: true,
  ),
  GauntletScenario(
    id: 'settle/transient-toast',
    lane: laneSettle,
    title: 'Transient toast',
    trap:
        'A message shows briefly then auto-dismisses. Catch it in its '
        'window.',
    built: true,
  ),

  // ── Lane B ──────────────────────────────────────────────────────────
  GauntletScenario(
    id: 'control/label-lie',
    lane: laneControls,
    title: 'Label vs. pixels disagree',
    trap: 'A button reads "Continue" but its semantic label is "Submit".',
    built: false,
  ),
  GauntletScenario(
    id: 'control/slider-semantic-value',
    lane: laneControls,
    title: 'Value only in semantics',
    trap:
        'A slider whose current value lives only in its semantic value, '
        'never as visible text.',
    built: false,
  ),
  GauntletScenario(
    id: 'control/expand-to-reach',
    lane: laneControls,
    title: 'Hidden until expanded',
    trap:
        'The target control is not in the tree until a section is '
        'expanded.',
    built: false,
  ),
  GauntletScenario(
    id: 'control/modal-trap',
    lane: laneControls,
    title: 'Modal focus trap',
    trap:
        'A dialog swallows outside taps. Dismiss it before anything else '
        'works.',
    built: false,
  ),
  GauntletScenario(
    id: 'control/lazy-offscreen',
    lane: laneControls,
    title: 'Lazy off-screen target',
    trap: 'The target list item only materialises after scrolling.',
    built: false,
  ),
  GauntletScenario(
    id: 'control/custom-paint-control',
    lane: laneControls,
    title: 'Custom-painted control',
    trap: 'A CustomPaint segmented control with hand-authored semantics.',
    built: false,
  ),

  // ── Lane C ──────────────────────────────────────────────────────────
  GauntletScenario(
    id: 'vision/object-id',
    lane: laneVision,
    title: 'Object ID in a photo',
    trap:
        'Tap a thing inside a photo. The semantics tree knows nothing '
        'about pixels.',
    built: true,
  ),
  GauntletScenario(
    id: 'vision/chart-read',
    lane: laneVision,
    title: 'Read an infographic',
    trap: 'Answer a question whose data lives only in a rendered chart.',
    built: true,
  ),
  GauntletScenario(
    id: 'vision/ocr-price',
    lane: laneVision,
    title: 'OCR text baked into an image',
    trap: 'A price rendered into a JPEG, not selectable text.',
    built: true,
  ),
  GauntletScenario(
    id: 'vision/count-spatial',
    lane: laneVision,
    title: 'Count / spatial reasoning',
    trap: 'How many of a thing are in the photo? Hide-n-seek.',
    built: true,
  ),
  GauntletScenario(
    id: 'vision/semantics-lie',
    lane: laneVision,
    title: 'Semantics hides a visual state',
    trap:
        'A tile painted as an error but semantically neutral. Only pixels '
        'catch it.',
    built: true,
  ),
];
