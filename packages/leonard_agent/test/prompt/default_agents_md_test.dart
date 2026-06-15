/// Guards the bundled operating guide that web hosts (DevTools) pin to the
/// system prompt in lieu of the CLI's file-based AGENTS.md.
library;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

void main() {
  test('kDefaultAgentsMd carries the methodology + Finishing rule', () {
    expect(kDefaultAgentsMd, isNotEmpty);
    expect(kDefaultAgentsMd, contains('# Operating Guide'));
    // The "Finishing" rule is what gates core.done on a VISIBLE success
    // state — its absence is what caused premature done in the web panel.
    expect(kDefaultAgentsMd, contains('## Finishing'));
    expect(kDefaultAgentsMd, contains('core.done'));
    expect(kDefaultAgentsMd, contains('one concrete step'));
  });

  test('kDefaultAgentsMdHash is non-empty and matches the content hash', () {
    expect(kDefaultAgentsMdHash, isNotEmpty);
    expect(kDefaultAgentsMdHash, equals(fnv1a32Hex(kDefaultAgentsMd)));
  });

  test('fnv1a32Hex is deterministic and sensitive to change', () {
    expect(fnv1a32Hex('hello'), equals(fnv1a32Hex('hello')));
    expect(fnv1a32Hex('hello'), isNot(equals(fnv1a32Hex('hellp'))));
    expect(fnv1a32Hex(''), isNotEmpty);
  });
}
