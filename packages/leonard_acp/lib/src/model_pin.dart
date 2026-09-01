/// Resolving a pinned model id against what an ACP agent actually offers.
///
/// Pure so it can be tested without a live agent — the resolution rules are
/// where a bad pin silently becomes the wrong model, which is exactly the
/// failure `pow-a9o` records (claude's tier names 400 on codex under ChatGPT
/// auth).
library;

/// Everything before an effort suffix: `gpt-5.6-sol[high]` -> `gpt-5.6-sol`.
///
/// codex-acp qualifies every model id with a reasoning effort, so the bare
/// `gpt-5.6-sol` that power_station's one-shot environment passes to
/// `codex exec --model` is not itself a valid ACP model id.
String baseModelId(String modelId) {
  final int i = modelId.indexOf('[');
  return i == -1 ? modelId : modelId.substring(0, i);
}

/// Resolve [want] against [available], given the session's [current] model.
///
/// Order:
///   1. an exact id match wins;
///   2. else, if [current] already carries the pinned base, keep it — the
///      agent's own effort default is respected rather than overridden;
///   3. else, a single matching variant is taken;
///   4. else null — ambiguous or absent, and the caller must refuse loud so
///      the operator names an effort explicitly.
String? resolveModelId({
  required String want,
  required List<String> available,
  String? current,
}) {
  if (available.contains(want)) return want;

  final List<String> variants = available
      .where((String id) => baseModelId(id) == want)
      .toList();
  if (variants.isEmpty) return null;

  if (current != null && baseModelId(current) == want) return current;

  return variants.length == 1 ? variants.single : null;
}
