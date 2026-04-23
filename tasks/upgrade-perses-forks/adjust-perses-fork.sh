#!/usr/bin/env bash
#
# adjust-perses-fork.sh
#
# Applies Red Hat / rhobs-specific patches to an upstream perses checkout
# so it can be used as the github.com/rhobs/perses fork.
#
# Expected to be run from the root of the perses repository, on the
# release-coo-1.5 branch (which should be based on upstream origin/main).
#
# What this script does:
#   1. Renames the Go module  github.com/perses/perses -> github.com/rhobs/perses
#      in go.mod and every .go file (excluding plugin download URLs that must
#      keep pointing to the upstream github.com/perses releases).
#   2. Renames the CUE module reference in cue/cue.mod/module.cue and all .cue files.
#   3. Updates the Makefile references that use the full module path.
#   4. Updates Go template files (.tmpl) that embed the module path.
#   5. Removes the .github/ directory (CI jobs are not needed in the fork).
#   6. Removes /plugins and /plugins-archive from .gitignore so the
#      pre-built plugin archives can be committed.
#   7. Creates an empty plugins-archive/ directory (archives are added separately).
#
# This script is idempotent: running it twice produces the same result.
#
# Usage:
#   cd /path/to/perses
#   bash /path/to/adjust-perses-fork.sh [branch]
#
#   branch: the fork branch name (default: release-coo-1.5)
#
set -euo pipefail

BRANCH="${1:-release-coo-1.5}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

OLD_MODULE="github.com/perses/perses"
NEW_MODULE="github.com/rhobs/perses"

echo "==> Repository root: $REPO_ROOT"
echo "==> Branch: $BRANCH"
echo "==> Renaming module: $OLD_MODULE -> $NEW_MODULE"
echo ""

# ---------------------------------------------------------------------------
# 1. go.mod  --  replace the module declaration
# ---------------------------------------------------------------------------
echo "--- Step 1: Update go.mod module path"
if grep -q "module ${OLD_MODULE}" go.mod; then
  sed -i.bak "s|module ${OLD_MODULE}|module ${NEW_MODULE}|" go.mod
  rm -f go.mod.bak
  echo "    go.mod updated"
else
  echo "    go.mod already uses ${NEW_MODULE} (skipped)"
fi

# ---------------------------------------------------------------------------
# 2. .go files  --  rewrite import paths
# ---------------------------------------------------------------------------
echo "--- Step 2: Update Go import paths in .go files"
# Exclude node_modules/, ui/ JS/TS frontend code (but include ui/*.go),
# and scripts/plugin/install_plugin.go which contains a GitHub URL for
# downloading plugins from the upstream perses-plugins repo.
GO_FILES=$(find . -name '*.go' \
  -not -path './node_modules/*' \
  -not -path './ui/node_modules/*' \
  -not -path './scripts/plugin/install_plugin.go' \
  -print)
COUNT=0
for f in $GO_FILES; do
  if grep -q "${OLD_MODULE}" "$f"; then
    sed -i.bak "s|${OLD_MODULE}|${NEW_MODULE}|g" "$f"
    rm -f "${f}.bak"
    COUNT=$((COUNT + 1))
  fi
done
echo "    Updated $COUNT .go files"

echo "    Skipped scripts/plugin/install_plugin.go (no module imports, only upstream plugin download URL)"

# ---------------------------------------------------------------------------
# 3. .cue files  --  rewrite module/import paths
# ---------------------------------------------------------------------------
echo "--- Step 3: Update CUE module/import paths in .cue files"
CUE_FILES=$(find ./cue -name '*.cue' -print 2>/dev/null || true)
COUNT=0
for f in $CUE_FILES; do
  if grep -q "${OLD_MODULE}" "$f"; then
    sed -i.bak "s|${OLD_MODULE}|${NEW_MODULE}|g" "$f"
    rm -f "${f}.bak"
    COUNT=$((COUNT + 1))
  fi
done
echo "    Updated $COUNT .cue files"

# Also update the internal test CUE files
TEST_CUE_FILES=$(find ./internal -name '*.cue' -print 2>/dev/null || true)
for f in $TEST_CUE_FILES; do
  if grep -q "${OLD_MODULE}" "$f"; then
    sed -i.bak "s|${OLD_MODULE}|${NEW_MODULE}|g" "$f"
    rm -f "${f}.bak"
  fi
done

# ---------------------------------------------------------------------------
# 4. Makefile  --  update hard-coded module paths
# ---------------------------------------------------------------------------
echo "--- Step 4: Update Makefile references"
if grep -q "${OLD_MODULE}" Makefile; then
  sed -i.bak "s|${OLD_MODULE}|${NEW_MODULE}|g" Makefile
  rm -f Makefile.bak
  echo "    Makefile updated"
else
  echo "    Makefile already correct (skipped)"
fi

# ---------------------------------------------------------------------------
# 5. Template files (.tmpl)  --  used by plugin/generate
# ---------------------------------------------------------------------------
echo "--- Step 5: Update template files (.tmpl)"
TMPL_FILES=$(find . -name '*.tmpl' -print 2>/dev/null || true)
COUNT=0
for f in $TMPL_FILES; do
  if grep -q "${OLD_MODULE}" "$f"; then
    sed -i.bak "s|${OLD_MODULE}|${NEW_MODULE}|g" "$f"
    rm -f "${f}.bak"
    COUNT=$((COUNT + 1))
  fi
done
echo "    Updated $COUNT .tmpl files"

# ---------------------------------------------------------------------------
# 6. Remove .github/ directory  (upstream CI not needed in fork)
# ---------------------------------------------------------------------------
echo "--- Step 6: Remove .github/ directory"
if [ -d .github ]; then
  rm -rf .github
  echo "    .github/ removed"
else
  echo "    .github/ already absent (skipped)"
fi

# ---------------------------------------------------------------------------
# 7. Update .gitignore  --  un-ignore /plugins and /plugins-archive
# ---------------------------------------------------------------------------
echo "--- Step 7: Update .gitignore (un-ignore plugins directories)"
if grep -q '^/plugins$' .gitignore 2>/dev/null; then
  sed -i.bak '/^\/plugins$/d' .gitignore
  rm -f .gitignore.bak
  echo "    Removed /plugins from .gitignore"
fi
if grep -q '^/plugins-archive$' .gitignore 2>/dev/null; then
  sed -i.bak '/^\/plugins-archive$/d' .gitignore
  rm -f .gitignore.bak
  echo "    Removed /plugins-archive from .gitignore"
fi

# ---------------------------------------------------------------------------
# 8. Ensure plugins-archive/ directory exists
# ---------------------------------------------------------------------------
echo "--- Step 8: Ensure plugins-archive/ directory exists"
mkdir -p plugins-archive
echo "    plugins-archive/ directory present"

# ---------------------------------------------------------------------------
# 9. Update plugin.yaml with latest upstream release versions
# ---------------------------------------------------------------------------
echo "--- Step 9: Update plugin.yaml with latest upstream versions"
PLUGIN_YAML="scripts/plugin/plugin.yaml"
PLUGINS_REPO="perses/perses-plugins"

if [ ! -f "$PLUGIN_YAML" ]; then
  echo "    WARNING: $PLUGIN_YAML not found, skipping plugin version update"
else
  if ! command -v gh &>/dev/null; then
    echo "    WARNING: gh CLI not available, skipping plugin version update"
    echo "    Install gh and re-run, or update $PLUGIN_YAML manually"
  else
    echo "    Fetching latest releases from ${PLUGINS_REPO}..."

    # Get all releases (tags are formatted as <lowercase-name>/v<version>)
    ALL_RELEASES=$(gh release list --repo "$PLUGINS_REPO" --limit 200 --json tagName --jq '.[].tagName')

    UPDATED=0
    while IFS= read -r PLUGIN_NAME; do
      # Release tags use lowercase plugin names
      LOWER_NAME=$(echo "$PLUGIN_NAME" | tr '[:upper:]' '[:lower:]')

      # Find the latest version for this plugin (tags: <name>/v<version>)
      LATEST_TAG=$(echo "$ALL_RELEASES" | grep "^${LOWER_NAME}/v" | sort -V | tail -1)

      if [ -z "$LATEST_TAG" ]; then
        echo "    WARNING: No release found for plugin ${PLUGIN_NAME}"
        continue
      fi

      # Extract version (strip the <name>/v prefix)
      LATEST_VERSION="${LATEST_TAG#${LOWER_NAME}/v}"

      # Get current version from plugin.yaml
      CURRENT_VERSION=$(grep -A1 "name: \"${PLUGIN_NAME}\"" "$PLUGIN_YAML" | grep 'version:' | sed 's/.*version: *"\(.*\)"/\1/')

      if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        continue
      fi

      echo "    ${PLUGIN_NAME}: ${CURRENT_VERSION} -> ${LATEST_VERSION}"
      sed -i.bak "/${PLUGIN_NAME}/,/version:/ s/version: \"${CURRENT_VERSION}\"/version: \"${LATEST_VERSION}\"/" "$PLUGIN_YAML"
      rm -f "${PLUGIN_YAML}.bak"
      UPDATED=$((UPDATED + 1))
    done < <(grep '^\- name:' "$PLUGIN_YAML" | sed 's/- name: *"\(.*\)"/\1/')

    if [ "$UPDATED" -eq 0 ]; then
      echo "    All plugins already at latest versions"
    else
      echo "    Updated $UPDATED plugin(s) in $PLUGIN_YAML"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 10. Clean old plugin archives
# ---------------------------------------------------------------------------
echo "--- Step 10: Remove old plugin archives"
if [ -d plugins-archive ] && ls plugins-archive/*.tar.gz &>/dev/null 2>&1; then
  rm -f plugins-archive/*.tar.gz
  echo "    Removed old plugin archives (will be re-downloaded by make build-api)"
else
  echo "    No old archives to clean"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==> Done. Summary of changes:"
echo "    - Go module renamed to ${NEW_MODULE}"
echo "    - All .go, .cue, .tmpl, and Makefile references updated"
echo "    - .github/ directory removed"
echo "    - .gitignore updated to track plugins-archive/"
echo "    - plugins-archive/ directory created"
echo "    - plugin.yaml updated to latest upstream versions"
echo ""
echo "Next steps:"
echo "  1. Run 'go mod tidy' to update go.sum"
echo "  2. Run 'make build-api' to download plugins and build"
echo "  3. Commit all changes as '[FORK] rename module and adjust for rhobs'"
