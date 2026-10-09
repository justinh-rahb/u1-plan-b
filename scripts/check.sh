#!/usr/bin/env bash
# This repo's own gate: it must pass from this repo's root, with no sibling repo cloned except
# lib_bespok3d. Exits non-zero on any failure.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The shared gate helpers and the detectors that enforce a workspace-wide rule live in one place.
# See lib_bespok3d/tooling/README.md. This is the only line that knows where they are.
B3D_TOOLING="${B3D_TOOLING:-$REPO_ROOT/lib_bespok3d/tooling}"
if [ ! -f "$B3D_TOOLING/gate-lib.sh" ]; then
    echo "The shared gate helpers are missing: the lib_bespok3d submodule is not checked out." >&2
    echo "Run this once from the repo root, then try again:" >&2
    echo "  git submodule sync --recursive && git submodule update --init --recursive" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$B3D_TOOLING/gate-lib.sh"

cd "$REPO_ROOT" || exit 1

echo ""
echo "u1-paxx-ab gate"

# The scripts are shell, so their suite is shell too: it runs them against fake updateEngine,
# upfileUnpack, curl, df and reboot, with no printer, no eMMC and no root.
run_check "paxx-ab tests" sh "$REPO_ROOT/tests/run.sh"
# The scripts have no .sh extension (they are placed as system-bins), so shellcheck_repo below would
# not find them on its own.
if command -v shellcheck > /dev/null 2>&1; then
    run_check "shellcheck files/bin" shellcheck "$REPO_ROOT"/files/bin/*
else
    skip_check "shellcheck files/bin" "not installed"
fi

release_trigger_check "$REPO_ROOT"
manifest_origin_check "$REPO_ROOT"
workflow_pinning_check "$REPO_ROOT"
em_dash_check "$REPO_ROOT"
shellcheck_repo "$REPO_ROOT"

gate_summary || exit 1
