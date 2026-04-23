#!/usr/bin/env bash
# adjust-perses-operator-fork.sh
#
# Purpose: Apply Red Hat fork patches to the perses-operator release-coo-1.5 branch.
# This script must be run from the root of the perses-operator checkout with
# the release-coo-1.5 branch checked out (based on upstream origin/main).
#
# What it does (replicating the pattern from the old rhobs/v0.3-golang_1_25 branch):
#
#   1. Renames the Go module from github.com/perses/perses-operator
#      to github.com/rhobs/perses-operator in go.mod and all .go files
#
#   2. Replaces all github.com/perses/perses imports with github.com/rhobs/perses
#      in go.mod and all .go files (complete replacement, same as old fork)
#
#   3. Updates the PROJECT file (kubebuilder config)
#
#   4. Removes the .github/ directory (upstream CI not needed in fork)
#
#   5. Runs go mod tidy
#
# Prerequisites:
#   - Go 1.25+ installed
#   - The release-coo-1.5 branch of github.com/rhobs/perses must exist
#   - You are on the release-coo-1.5 branch of this repo
#
# Usage:
#   cd /path/to/perses-operator
#   git checkout release-coo-1.5
#   bash /path/to/adjust-perses-operator-fork.sh [branch]
#
#   branch: the rhobs/perses fork branch to depend on (default: release-coo-1.5)

set -euo pipefail

BRANCH="${1:-release-coo-1.5}"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)/projects/perses-operator"

if [[ ! -f "${REPO_ROOT}/go.mod" ]]; then
    echo "ERROR: go.mod not found at ${REPO_ROOT}/go.mod"
    echo "Make sure the script is run from the correct location."
    exit 1
fi

cd "${REPO_ROOT}"

echo "=== Working in: $(pwd)"
echo "=== Current branch: $(git branch --show-current)"
echo "=== rhobs/perses fork branch: $BRANCH"
echo ""

# ---------------------------------------------------------------
# Step 1: Rename the operator module in go.mod
# ---------------------------------------------------------------
echo "--- Step 1: Renaming operator module in go.mod ---"
if grep -q "module github.com/perses/perses-operator" go.mod; then
    sed -i.bak "s|module github.com/perses/perses-operator|module github.com/rhobs/perses-operator|" go.mod
    rm -f go.mod.bak
    echo "    go.mod module updated"
else
    echo "    go.mod already uses rhobs (skipped)"
fi

# ---------------------------------------------------------------
# Step 2: Replace perses/perses dependency with rhobs/perses in go.mod
#         Use go get to fetch from the fork branch (no release tags exist)
# ---------------------------------------------------------------
echo "--- Step 2: Replacing perses/perses with rhobs/perses in go.mod ---"
if grep -q "github.com/perses/perses " go.mod; then
    # Remove the upstream dependency first
    go mod edit -droprequire github.com/perses/perses
    # Fetch the fork from the branch — go get resolves it to a pseudo-version
    if go get "github.com/rhobs/perses@${BRANCH}"; then
        echo "    go.mod dependency updated to rhobs/perses@${BRANCH}"
    else
        echo "    WARNING: go get failed (fork branch may not be pushed yet)"
        echo "    You will need to run this manually after pushing the fork:"
        echo "      go get github.com/rhobs/perses@${BRANCH}"
    fi
elif grep -q "github.com/rhobs/perses " go.mod; then
    echo "    go.mod already uses rhobs/perses (skipped)"
else
    echo "    WARNING: no perses dependency found in go.mod"
fi

# ---------------------------------------------------------------
# Step 3: Update all Go import paths in .go files
# ---------------------------------------------------------------
echo "--- Step 3: Updating Go import paths in .go files ---"
COUNT=0
while IFS= read -r -d '' f; do
    CHANGED=false
    if grep -q "github.com/perses/perses-operator" "$f"; then
        sed -i.bak "s|github.com/perses/perses-operator|github.com/rhobs/perses-operator|g" "$f"
        rm -f "${f}.bak"
        CHANGED=true
    fi
    if grep -q "github.com/perses/perses/" "$f"; then
        sed -i.bak "s|github.com/perses/perses/|github.com/rhobs/perses/|g" "$f"
        rm -f "${f}.bak"
        CHANGED=true
    fi
    if [ "$CHANGED" = true ]; then
        COUNT=$((COUNT + 1))
    fi
done < <(find . -name '*.go' -not -path './vendor/*' -print0)
echo "    Updated $COUNT .go files"

# ---------------------------------------------------------------
# Step 4: Update the PROJECT file (kubebuilder scaffold config)
# ---------------------------------------------------------------
echo "--- Step 4: Updating PROJECT file ---"
if grep -q "github.com/perses/perses-operator" PROJECT; then
    sed -i.bak "s|github.com/perses/perses-operator|github.com/rhobs/perses-operator|g" PROJECT
    rm -f PROJECT.bak
    echo "    PROJECT file updated"
else
    echo "    PROJECT file already correct (skipped)"
fi

# ---------------------------------------------------------------
# Step 5: Remove .github/ directory (upstream CI not used in fork)
# ---------------------------------------------------------------
echo "--- Step 5: Removing .github/ directory ---"
if [[ -d ".github" ]]; then
    rm -rf .github
    echo "    .github/ directory removed"
else
    echo "    .github/ directory already absent"
fi

# ---------------------------------------------------------------
# Step 6: Run go mod tidy
# ---------------------------------------------------------------
echo "--- Step 6: Running go mod tidy ---"
echo "    NOTE: This may fail if the rhobs/perses fork branch is not yet pushed."
echo ""
if go mod tidy; then
    echo "    go mod tidy succeeded"
else
    echo ""
    echo "    WARNING: go mod tidy failed. This is expected if:"
    echo "      - The rhobs/perses ${BRANCH} branch is not yet pushed"
    echo ""
    echo "    After pushing the fork, run:"
    echo "      go get github.com/rhobs/perses@${BRANCH}"
    echo "      go mod tidy"
fi

echo ""
echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  1. Verify the build: make bin"
echo "  2. Run tests: make test"
echo "  3. Review changes: git diff"
echo "  4. Commit: git add -A && git commit -m '[FORK] rename module and use rhobs/perses fork'"
echo "  5. Push: git push rhobs release-coo-1.5"
