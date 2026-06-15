/// Diagnostic record produced by [InteractiveSemanticsAuditor] when a
/// candidate interactable widget lacks an enclosing semantics annotation.
///
/// Surfaced via the host VM service extension
/// `ext.exploration.core.diagnostics_warnings`. Connect-time only;
/// not a per-turn observation contributor.
class InteractiveSemanticsWarning {
  InteractiveSemanticsWarning({
    required this.widgetType,
    required this.location,
    required this.suggestedFixPointer,
  });

  /// Runtime type name of the offending widget (e.g. `'GestureDetector'`).
  final String widgetType;

  /// Location string, sourced from `Element.debugGetCreatorChain(1)` when
  /// available; falls back to `widget.runtimeType.toString()`.
  final String location;

  /// Canonical fix-pointer message. Use [kExtensionGuideFixPointer].
  final String suggestedFixPointer;

  Map<String, Object?> toJson() => <String, Object?>{
        'widget_type': widgetType,
        'location': location,
        'suggested_fix_pointer': suggestedFixPointer,
      };
}

/// Canonical fix-pointer message — referenced verbatim by tests and
/// surfaced to users in every warning record.
const String kExtensionGuideFixPointer =
    "These widgets won't be visible to the agent. Add semantics annotations, "
    'or write a plugin that exposes them — see '
    'https://docs.example.com/exploration/plugin-authoring (cx6.35).';
