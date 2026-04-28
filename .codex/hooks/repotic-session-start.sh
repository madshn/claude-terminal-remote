#!/usr/bin/env bash
# Codex SessionStart hook — registers session in team_sessions.
# Thin wrapper; see register.sh for actual logic.
# CRITICAL: stdout from a Codex hook is injected as developer context.
#          register.sh sends all output to /dev/null; do not echo here.
set -uo pipefail
REPOTIC_RUNTIME="codex"
# shellcheck source=register.sh
source "$(dirname "$0")/register.sh"
repotic_run_start
exit 0
