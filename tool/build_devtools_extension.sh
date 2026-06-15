#!/usr/bin/env bash
# tool/build_devtools_extension.sh
#
# Builds the leonard_devtools panel and copies the compiled web
# bundle into both extension/devtools/build/ destinations:
#
#   - packages/leonard_devtools/extension/devtools/build/
#       Used for standalone development against devtools_extensions's
#       simulated DevTools env.
#
#   - packages/leonard_flutter/extension/devtools/build/
#       The host package whose pubspec dep triggers DevTools'
#       auto-discovery in consumer apps (sample_app et al.).
#
# Both destinations are gitignored — re-run this script after any
# change to packages/leonard_devtools/{lib,web,pubspec.yaml}.
# CI runs this script before analyze/test so PRs that break the build
# fail at merge.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PANEL="$ROOT/packages/leonard_devtools"
HOST="$ROOT/packages/leonard_flutter"
# Fail loudly if a rename orphaned these paths (guard against silent rot).
for d in "$PANEL" "$HOST"; do
  [ -d "$d" ] || { echo "build_devtools_extension: expected package dir missing: $d" >&2; exit 1; }
done
cd "$PANEL"

# This repo is a Dart pub *workspace* (root `lenny_workspace`, members use
# `resolution: workspace`) whose members require the Flutter SDK
# (leonard_dio et al. declare `flutter: sdk: flutter`). On a fresh clone the
# workspace is unresolved — pubspec.lock and .dart_tool are gitignored.
#
# Both the resolve and the build_and_copy run go through Flutter's bundled
# toolchain (`flutter pub …`), NEVER bare `dart`. If the `dart` on PATH is a
# standalone SDK (not Flutter-aware), `dart run` re-resolves this Flutter
# workspace with `dart pub` and fails:
#   "Because leonard_dio requires the Flutter SDK, version solving failed.
#    Flutter users should use `flutter pub` instead of `dart pub`."
# `flutter pub get` + `flutter pub run` always use Flutter's own Dart, so this
# works regardless of which `dart` happens to be first on PATH.
flutter pub get

flutter pub run devtools_extensions build_and_copy \
  --source=. \
  --dest=extension/devtools
flutter pub run devtools_extensions build_and_copy \
  --source=. \
  --dest=../leonard_flutter/extension/devtools
echo "✓ leonard_devtools bundles built into both destinations"
