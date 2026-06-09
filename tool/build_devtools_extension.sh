#!/usr/bin/env bash
# tool/build_devtools_extension.sh
#
# Builds the exploration_devtools panel and copies the compiled web
# bundle into both extension/devtools/build/ destinations:
#
#   - packages/exploration_devtools/extension/devtools/build/
#       Used for standalone development against devtools_extensions's
#       simulated DevTools env.
#
#   - packages/exploration_flutter/extension/devtools/build/
#       The host package whose pubspec dep triggers DevTools'
#       auto-discovery in consumer apps (sample_app et al.).
#
# Both destinations are gitignored — re-run this script after any
# change to packages/exploration_devtools/{lib,web,pubspec.yaml}.
# CI runs this script before analyze/test so PRs that break the build
# fail at merge.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/packages/exploration_devtools"

# This repo is a Dart pub *workspace* (root `lenny_workspace`, members use
# `resolution: workspace`) whose members require the Flutter SDK
# (exploration_dio et al. declare `flutter: sdk: flutter`). On a fresh clone the
# workspace is unresolved — pubspec.lock and .dart_tool are gitignored — so the
# `dart run` calls below would trigger an implicit `dart pub get` at the
# workspace root, which fails:
#   "Because exploration_dio requires the Flutter SDK, version solving failed.
#    Flutter users should use `flutter pub` instead of `dart pub`."
# Resolve the whole workspace with Flutter's pub up front (running it from a
# member resolves every package); the build_and_copy `dart run` calls then reuse
# the valid package_config instead of re-solving with the wrong tool.
flutter pub get

dart run devtools_extensions build_and_copy \
  --source=. \
  --dest=extension/devtools
dart run devtools_extensions build_and_copy \
  --source=. \
  --dest=../exploration_flutter/extension/devtools
echo "✓ exploration_devtools bundles built into both destinations"
