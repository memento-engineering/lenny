/// Spike-local component vocabulary for the "button" catalog type.
///
/// The catalog binds three Dart classes from THREE different packages:
/// `Node` (package:perception), `Field` (spike3 — reused value leaf), and
/// `CounterButton` (this file). That spread is deliberate A2 evidence: the
/// generated registry's import parameterization handles all three.
library;

import 'package:perception/perception.dart';
import 'package:spike3_schema_roundtrip/src/field.dart';

import 'actionable.dart';

/// Builder-invocation counts per component id (Perception.key).
///
/// Test instrumentation: tests clear this, then assert that a routed action
/// rebuilds EXACTLY the target subtree (target's count increments, unrelated
/// components' counts do not).
final Map<Object, int> buttonBuildCounts = {};

/// "button" catalog type: a pressable control whose LIVE state holds an int
/// counter. The counter lives in [CounterButtonState], not in the config —
/// the setState flavor of the action round-trip.
class CounterButton extends StatefulPerception {
  const CounterButton({required this.label, super.key});

  final String label;

  @override
  CounterButtonState createState() => CounterButtonState();
}

class CounterButtonState extends PerceptionState<CounterButton>
    implements ActionableState {
  int count = 0;

  @override
  Perception build(PerceptionContext context) {
    buttonBuildCounts.update(
      perception.key ?? '(unkeyed)',
      (n) => n + 1,
      ifAbsent: () => 1,
    );
    // Rendered projection: a spike3 Field leaf showing the live count.
    return Field(name: perception.label, value: '$count');
  }

  @override
  ActionOutcome handleAction(String name, Map<String, Object?> context) {
    final from = count;
    switch (name) {
      case 'press':
        final amount = context['amount'] ?? 1;
        if (amount is! int) {
          return PayloadError(
            'action "press": context.amount must be an integer when '
            'present, got: $amount (${amount.runtimeType})',
          );
        }
        perceived(() => count += amount);
        return HandledChange({
          'count': {'from': from, 'to': count},
        });
      case 'set':
        final value = context['value'];
        if (value is! int) {
          return PayloadError(
            'action "set": context.value must be an integer, got: '
            '$value (${value.runtimeType})',
          );
        }
        perceived(() => count = value);
        return HandledChange({
          'count': {'from': from, 'to': count},
        });
      default:
        // The router only dispatches catalog-declared actions; reaching here
        // means the catalog and this handler have drifted — fail loudly.
        throw StateError(
          'catalog/handler drift: catalog declares action "$name" for type '
          '"button" but CounterButtonState has no implementation for it',
        );
    }
  }
}
