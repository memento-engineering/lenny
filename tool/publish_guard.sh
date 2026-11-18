#!/usr/bin/env bash
# Refuses a release tag whose package does not match it, before the publish
# workflow opens any publishing path (lenny#the-publish-workflow-guards-every-
# tag-before-it-publishes, enforcing items 3 and 5 of
# memento-engineering#a-release-is-a-bump-pr-then-a-guarded-tag-push).
#
#   publish_guard.sh <tag> [<package directory>]
#
# The working directory is the repository root. The tag is
# `<package>-v<version>`; without a directory the package is looked up under
# packages/ then grid_assets/. Four checks all run, so one run names every
# mismatch:
#
#   name        the pubspec names the tag's package
#   version     the pubspec version is exactly the tag's version
#   changelog   CHANGELOG.md has a `## <version>` (or `## [<version>]`) heading
#   dependency  each runtime dependency that is a sibling package of this
#               repository has the version its own pubspec declares listed on
#               pub.dev (dev_dependencies and dependency_overrides are not read)
#
# Each pass prints `publish_guard: ok <check>: <detail>` to stdout and each
# failure `publish_guard: FAIL <check>: <detail>` to stderr. A pub.dev listing
# that cannot be read, or a dependency list that cannot be parsed, fails
# (fail closed).
#
# Exit: 0 every check passed; 1 a check failed; 64 usage or a malformed tag;
# 69 curl or jq is missing.
#
# Runs under the bash 3.2 macOS ships: no mapfile, associative arrays or
# case-folding expansions.
set -euo pipefail

readonly PUB_DEV_API='https://pub.dev/api/packages'
readonly TAG_PATTERN='^([a-z][a-z0-9_]*)-v([0-9]+[.][0-9]+[.][0-9]+(-[0-9A-Za-z.-]+)?([+][0-9A-Za-z.-]+)?)$'

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'usage: publish_guard.sh <tag> [<package directory>]\n' >&2
  exit 64
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf 'publish_guard: FAIL tools: requires curl and jq on PATH\n' >&2
  exit 69
fi

tag="$1"
if [[ ! "$tag" =~ $TAG_PATTERN ]]; then
  printf "publish_guard: FAIL tag: '%s' is not <package>-v<version>\n" \
    "$tag" >&2
  exit 64
fi
package="${BASH_REMATCH[1]}"
tag_version="${BASH_REMATCH[2]}"

failed=0

ok() {
  printf 'publish_guard: ok %s: %s\n' "$1" "$2"
}

fail() {
  printf 'publish_guard: FAIL %s: %s\n' "$1" "$2" >&2
  failed=1
}

# Drops leading and trailing whitespace from $1.
trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# Drops one pair of surrounding single or double quotes from $1.
unquote() {
  local value="$1"
  if [[ ${#value} -ge 2 ]]; then
    if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf '%s' "$value"
}

# Prints the value of the first line of pubspec $1 starting `$2:`, without
# surrounding whitespace, a trailing ` #` comment or one pair of quotes.
# Prints nothing when no such line exists.
read_scalar() {
  local file="$1" field="$2" line value
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$field:"* ]]; then
      value="${line#"$field:"}"
      value="${value%% #*}"
      value="$(trim "$value")"
      unquote "$value"
      return 0
    fi
  done <"$file"
  return 0
}

# --- directory ---------------------------------------------------------------

if [[ $# -eq 2 ]]; then
  dir="$2"
  while [[ "$dir" == */ && "$dir" != / ]]; do
    dir="${dir%/}"
  done
  if [[ ! -f "$dir/pubspec.yaml" ]]; then
    fail pubspec "no pubspec.yaml at $dir"
    exit 1
  fi
elif [[ -f "packages/$package/pubspec.yaml" ]]; then
  dir="packages/$package"
elif [[ -f "grid_assets/$package/pubspec.yaml" ]]; then
  dir="grid_assets/$package"
else
  fail pubspec "no pubspec.yaml for $package under packages/ or grid_assets/"
  exit 1
fi
pubspec="$dir/pubspec.yaml"

# --- name --------------------------------------------------------------------

pubspec_name="$(read_scalar "$pubspec" name)"
if [[ -z "$pubspec_name" ]]; then
  fail name "$pubspec has no name line"
elif [[ "$pubspec_name" != "$package" ]]; then
  fail name "$pubspec names $pubspec_name, not $package"
else
  ok name "$pubspec names $package"
fi

# --- version -----------------------------------------------------------------

pubspec_version="$(read_scalar "$pubspec" version)"
if [[ -z "$pubspec_version" ]]; then
  fail version "$pubspec has no version line"
elif [[ "$pubspec_version" != "$tag_version" ]]; then
  fail version \
    "tag $tag names $tag_version but $pubspec reads $pubspec_version"
else
  ok version "$pubspec reads $tag_version"
fi

# --- changelog ---------------------------------------------------------------

changelog="$dir/CHANGELOG.md"
if [[ ! -f "$changelog" ]]; then
  fail changelog "$changelog does not exist"
else
  heading_found=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%"${line##*[![:space:]]}"}"
    # Quoted operands are fixed strings: dots are literal, and a longer
    # prerelease heading does not satisfy the shorter version.
    if [[ "$line" == "## $tag_version" ||
      "$line" == "## [$tag_version]" ||
      "$line" == "## $tag_version "* ||
      "$line" == "## [$tag_version] "* ]]; then
      heading_found=1
      break
    fi
  done <"$changelog"
  if [[ "$heading_found" -eq 1 ]]; then
    ok changelog "$changelog has a '## $tag_version' heading"
  else
    fail changelog "$changelog has no '## $tag_version' heading"
  fi
fi

# --- dependency --------------------------------------------------------------

# Collects the entry names of the column-0 `dependencies:` block into
# dependency_names (newline-separated). Returns 1 on an inline map it cannot
# read.
dependency_names=''
read_dependency_names() {
  local in_block=0 indent=-1 line stripped count name value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$in_block" -eq 0 ]]; then
      if [[ "$line" == 'dependencies:'* ]]; then
        value="${line#dependencies:}"
        value="${value%%#*}"
        value="$(trim "$value")"
        if [[ -z "$value" ]]; then
          in_block=1
        elif [[ "$value" == '{}' ]]; then
          return 0
        else
          return 1
        fi
      fi
      continue
    fi
    # Inside the block.
    if [[ -z "$(trim "$line")" ]]; then
      continue
    fi
    case "${line:0:1}" in
      ' ' | '#') ;;
      *) return 0 ;;
    esac
    stripped="${line#"${line%%[! ]*}"}"
    if [[ "$stripped" == '#'* ]]; then
      continue
    fi
    count=$((${#line} - ${#stripped}))
    if [[ "$indent" -lt 0 ]]; then
      indent="$count"
    fi
    if [[ "$count" -ne "$indent" ]]; then
      continue
    fi
    name="${stripped%%:*}"
    name="$(unquote "$(trim "$name")")"
    dependency_names="$dependency_names$name"$'\n'
  done <"$pubspec"
  return 0
}

if ! read_dependency_names; then
  fail dependency "$pubspec has an inline dependencies map this guard cannot read"
else
  siblings=0
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ -f "packages/$name/pubspec.yaml" ]]; then
      sibling_pubspec="packages/$name/pubspec.yaml"
    elif [[ -f "grid_assets/$name/pubspec.yaml" ]]; then
      sibling_pubspec="grid_assets/$name/pubspec.yaml"
    else
      continue
    fi
    siblings=$((siblings + 1))

    declared="$(read_scalar "$sibling_pubspec" version)"
    if [[ -z "$declared" ]]; then
      fail dependency "$sibling_pubspec has no version line"
      continue
    fi

    url="$PUB_DEV_API/$name"
    if ! body="$(curl --fail --silent --show-error --location --retry 2 \
      --header 'Accept: application/vnd.pub.v2+json' "$url")"; then
      fail dependency "cannot read $url"
      continue
    fi
    # An empty body is unreadable too: jq accepts it and prints nothing.
    if [[ -z "$(trim "$body")" ]] ||
      ! listed="$(printf '%s' "$body" | jq -r '.versions[].version' 2>/dev/null)"; then
      fail dependency "cannot read $url"
      continue
    fi
    if grep -Fxq -- "$declared" <<<"$listed"; then
      ok dependency "$name $declared is published"
    else
      fail dependency \
        "$name $declared ($sibling_pubspec) is not published on pub.dev"
    fi
  done <<<"$dependency_names"
  if [[ "$siblings" -eq 0 ]]; then
    ok dependency 'no sibling dependencies'
  fi
fi

# --- verdict -----------------------------------------------------------------

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
printf 'publish_guard: PASS %s\n' "$tag"
