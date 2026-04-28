#!/usr/bin/env bash
# Codex Stop hook — marks session completed in team_sessions.
# Thin wrapper; see register.sh for actual logic.
set -uo pipefail
REPOTIC_RUNTIME="codex"
# shellcheck source=register.sh
source "$(dirname "$0")/register.sh"
repotic_run_stop
exit 0
