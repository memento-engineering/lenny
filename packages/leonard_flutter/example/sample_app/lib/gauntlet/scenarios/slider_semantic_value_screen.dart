import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scenario_oracle.dart';

/// Lane B — value only in semantics.
///
/// A volume slider is preset to 7, but the number is NEVER shown as visible
/// text — it exists only as the slider's semantic value (via
/// [Slider.semanticFormatterCallback]). An agent that reads only pixels
/// can't state the value; it has to read the semantics node.
///
/// Answer oracle: expected.value == 7.
class SliderSemanticValueScreen extends StatefulWidget {
  const SliderSemanticValueScreen({super.key});

  static const String scenarioId = 'control/slider-semantic-value';
  static const int presetValue = 7;

  @override
  State<SliderSemanticValueScreen> createState() =>
      _SliderSemanticValueScreenState();
}

class _SliderSemanticValueScreenState extends State<SliderSemanticValueScreen> {
  double _value = SliderSemanticValueScreen.presetValue.toDouble();

  @override
  Widget build(BuildContext context) {
    return ScenarioHost(
      id: SliderSemanticValueScreen.scenarioId,
      expected: const <String, Object?>{
        'value': SliderSemanticValueScreen.presetValue,
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Slider value'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => context.go('/gauntlet'),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Volume'),
              const SizedBox(height: 8),
              Slider(
                value: _value,
                min: 0,
                max: 10,
                divisions: 10,
                // The ONLY place the value is exposed: the semantic value.
                // No visible number anywhere on screen.
                semanticFormatterCallback: (double v) => v.round().toString(),
                onChanged: (double v) => setState(() => _value = v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
