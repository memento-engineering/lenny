/// A bad pin silently becoming the wrong model is the `pow-a9o` failure class.
/// These pin the resolution rules against the real codex-acp catalogue.
library;

import 'package:leonard_acp/leonard_acp.dart';
import 'package:test/test.dart';

/// The ids codex-acp 1.6.2 actually reports, trimmed to the relevant families.
const List<String> _codexCatalogue = <String>[
  'gpt-5.6-sol[low]',
  'gpt-5.6-sol[medium]',
  'gpt-5.6-sol[high]',
  'gpt-5.6-sol[xhigh]',
  'gpt-5.6-sol[max]',
  'gpt-5.6-sol[ultra]',
  'gpt-5.6-terra[low]',
  'gpt-5.6-terra[high]',
  'gpt-5.5[low]',
];

void main() {
  group('baseModelId', () {
    test('strips the effort suffix', () {
      expect(baseModelId('gpt-5.6-sol[xhigh]'), 'gpt-5.6-sol');
    });

    test('leaves an unqualified id alone', () {
      expect(baseModelId('gpt-5.6-sol'), 'gpt-5.6-sol');
    });
  });

  group('resolveModelId', () {
    test('an exact id wins outright', () {
      expect(
        resolveModelId(
          want: 'gpt-5.6-sol[max]',
          available: _codexCatalogue,
          current: 'gpt-5.6-sol[low]',
        ),
        'gpt-5.6-sol[max]',
      );
    });

    test('a base pin keeps the current effort when the base matches', () {
      // The real case: power_station pins the bare `gpt-5.6-sol`, codex-acp
      // already sits on [xhigh]. Respect the agent's own effort default.
      expect(
        resolveModelId(
          want: kCodexPinnedModel,
          available: _codexCatalogue,
          current: 'gpt-5.6-sol[xhigh]',
        ),
        'gpt-5.6-sol[xhigh]',
      );
    });

    test('a base pin MOVES off a different family', () {
      // Current is terra, pin is sol, and sol has six variants — ambiguous, so
      // refuse rather than silently picking an effort.
      expect(
        resolveModelId(
          want: kCodexPinnedModel,
          available: _codexCatalogue,
          current: 'gpt-5.6-terra[high]',
        ),
        isNull,
      );
    });

    test('a base pin with exactly one variant resolves unambiguously', () {
      expect(
        resolveModelId(
          want: 'gpt-5.5',
          available: _codexCatalogue,
          current: 'gpt-5.6-terra[high]',
        ),
        'gpt-5.5[low]',
      );
    });

    test('an unknown model resolves to null so the caller refuses loud', () {
      expect(
        resolveModelId(
          want: 'opus',
          available: _codexCatalogue,
          current: 'gpt-5.6-sol[xhigh]',
        ),
        isNull,
        reason: 'claude tier names on codex are exactly what pow-a9o 400s on',
      );
    });

    test('resolves with no current model set', () {
      expect(
        resolveModelId(want: 'gpt-5.5', available: _codexCatalogue),
        'gpt-5.5[low]',
      );
    });

    test('an unqualified catalogue still matches exactly', () {
      expect(
        resolveModelId(
          want: 'gpt-5.6-sol',
          available: const <String>['gpt-5.6-sol', 'gpt-5.5'],
        ),
        'gpt-5.6-sol',
      );
    });
  });
}
