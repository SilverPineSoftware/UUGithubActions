#!/usr/bin/env bash
#
# uu-bump-action-refs.sh
#
# Rewrites every `uses: SilverPineSoftware/UUKotlinBuild/.github/...@<ref>`
# line under `.github/` to use a single target ref.
#
# Usage:
#   scripts/uu-bump-action-refs.sh                # uses version= from gradle.properties
#   scripts/uu-bump-action-refs.sh 0.0.23         # uses an explicit ref (no leading 'v')
#   scripts/uu-bump-action-refs.sh v0.0.23        # also fine, written verbatim
#
# Idempotent: re-running with the same ref leaves files untouched.
# Touches `.yml` and `.yaml` files. Only rewrites refs that target
# `SilverPineSoftware/UUKotlinBuild`; external refs like `actions/checkout@v4`
# are left alone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GH_DIR="$REPO_ROOT/.github"
GRADLE_PROPERTIES="$REPO_ROOT/gradle.properties"

if [ ! -d "$GH_DIR" ]; then
    echo "::error::No .github directory found at $GH_DIR" >&2
    exit 1
fi

if [ "$#" -gt 0 ]; then
    NEW_REF="$1"
else
    if [ ! -f "$GRADLE_PROPERTIES" ]; then
        echo "::error::gradle.properties not found at $GRADLE_PROPERTIES" >&2
        echo "         Pass an explicit ref as the first argument, e.g. '0.0.23'." >&2
        exit 1
    fi
    NEW_REF="$(grep '^version=' "$GRADLE_PROPERTIES" | head -n 1 | sed 's/^version=//')"
    if [ -z "$NEW_REF" ]; then
        echo "::error::No 'version=' line found in gradle.properties" >&2
        exit 1
    fi
fi

echo "Rewriting SilverPineSoftware/UUKotlinBuild refs to @$NEW_REF"

UPDATED=0
SCANNED=0

while IFS= read -r -d '' file; do
    SCANNED=$((SCANNED + 1))
    # Quick skip if the file has no matching refs.
    if ! grep -qiE 'SilverPineSoftware/UUKotlinBuild/[^@[:space:]]+@[^[:space:]]+' "$file"; then
        continue
    fi

    BEFORE_HASH="$(shasum "$file" | awk '{print $1}')"

    # In-place rewrite: keep the path before @, replace whatever follows @ with $NEW_REF.
    # Case-insensitive on the org/repo to tolerate "Silverpine" vs "SilverPine".
    UU_NEW_REF="$NEW_REF" perl -i -pe '
        s{
            (SilverPineSoftware/UUKotlinBuild/[^@\s]+)
            @
            \S+
        }
        {$1 . "@" . $ENV{UU_NEW_REF}}gixe;
    ' "$file"

    AFTER_HASH="$(shasum "$file" | awk '{print $1}')"

    if [ "$BEFORE_HASH" != "$AFTER_HASH" ]; then
        UPDATED=$((UPDATED + 1))
        echo "  updated: ${file#"$REPO_ROOT/"}"
    fi
done < <(find "$GH_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)

echo
echo "Scanned $SCANNED file(s); updated $UPDATED."
if [ "$UPDATED" -eq 0 ]; then
    echo "Nothing to do — all refs already point to @$NEW_REF."
fi
