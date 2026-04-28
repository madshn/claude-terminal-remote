#!/usr/bin/env bash
# Shared session registration logic for repotic hooks.
# Sourced by per-runtime hook entry scripts (Claude SessionStart, Codex SessionStart, etc.).
#
# Contract: caller sets REPOTIC_RUNTIME (e.g. "claude", "codex") BEFORE sourcing,
# then calls repotic_run_start or repotic_run_stop. All output goes to /dev/null;
# fire-and-forget — failures are OK, the reaper catches stale rows.
#
# Note: stdout from a Codex hook is injected as developer context into the session.
# All curl/jq output therefore goes to /dev/null 2>&1 — never let this script print.

set -uo pipefail

REPOTIC_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ0cXF1bWxncG9odHFqYXJ6a3VhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc2OTUxMDksImV4cCI6MjA4MzI3MTEwOX0.x-8QnxdKPVJoyvmAKg-N83t5AIADgQDlicDnzzGeo0I"
REPOTIC_SUPABASE_URL="https://btqqumlgpohtqjarzkua.supabase.co"

# Read hook input from stdin once and extract common fields.
# Falls back to $PWD when the runtime doesn't include cwd in the payload (Codex).
repotic_read_input() {
  local input
  input="$(cat)"
  REPOTIC_SESSION_ID="$(printf '%s' "$input" | jq -r '.session_id // empty')"
  REPOTIC_CWD="$(printf '%s' "$input" | jq -r '.cwd // empty')"
  [ -z "$REPOTIC_CWD" ] && REPOTIC_CWD="$PWD"
}

# Resolve actor (via actor-map.sh in the same dir) and repo name from cwd.
repotic_resolve_actor_repo() {
  # shellcheck source=actor-map.sh
  source "$(dirname "${BASH_SOURCE[0]}")/actor-map.sh"
  REPOTIC_ACTOR="$(repotic_actor_for_cwd "$REPOTIC_CWD")"
  REPOTIC_REPO="unknown"
  local relative="${REPOTIC_CWD#/Users/madsnissen/}"
  if [[ "$relative" =~ ^(team|ops|builds|crafts|oss)/([^/]+) ]]; then
    REPOTIC_REPO="madshn/${BASH_REMATCH[2]}"
  fi
}

# team_sessions id format: <actor>.local.<runtime>.<short_id>
# Runtime is in the id so a Claude session and Codex session in the same repo
# can never collide on a 12-char-prefix coincidence (~1-in-2^48 but real).
repotic_make_session_id() {
  local short_id="${REPOTIC_SESSION_ID:0:12}"
  REPOTIC_TS_ID="${REPOTIC_ACTOR}.local.${REPOTIC_RUNTIME}.${short_id}"
}

repotic_call_start_rpc() {
  curl -fsS -X POST "${REPOTIC_SUPABASE_URL}/rest/v1/rpc/repotic_session_start" \
    -H "apikey: ${REPOTIC_ANON_KEY}" \
    -H "Authorization: Bearer ${REPOTIC_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -H "Content-Profile: rightaim" \
    -d "$(jq -n \
      --arg id "$REPOTIC_TS_ID" \
      --arg actor "$REPOTIC_ACTOR" \
      --arg repo "$REPOTIC_REPO" \
      --arg workdir "$REPOTIC_CWD" \
      --arg runtime "$REPOTIC_RUNTIME" \
      '{p_id: $id, p_actor: $actor, p_repo: $repo, p_workdir: $workdir, p_runtime: $runtime}')" \
    >/dev/null 2>&1 || true
}

repotic_call_stop_rpc() {
  curl -fsS -X POST "${REPOTIC_SUPABASE_URL}/rest/v1/rpc/repotic_session_stop" \
    -H "apikey: ${REPOTIC_ANON_KEY}" \
    -H "Authorization: Bearer ${REPOTIC_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -H "Content-Profile: rightaim" \
    -d "$(jq -n \
      --arg id "$REPOTIC_TS_ID" \
      '{p_id: $id, p_exit_reason: "session_stop"}')" \
    >/dev/null 2>&1 || true
}

# Top-level entry points. Each hook script sets REPOTIC_RUNTIME, sources this lib,
# and calls one of these.
repotic_run_start() {
  : "${REPOTIC_RUNTIME:?REPOTIC_RUNTIME must be set before sourcing register.sh}"
  repotic_read_input
  [ -n "$REPOTIC_SESSION_ID" ] || return 0
  [ -n "$REPOTIC_CWD" ] || return 0
  repotic_resolve_actor_repo
  repotic_make_session_id
  repotic_call_start_rpc
}

repotic_run_stop() {
  : "${REPOTIC_RUNTIME:?REPOTIC_RUNTIME must be set before sourcing register.sh}"
  repotic_read_input
  [ -n "$REPOTIC_SESSION_ID" ] || return 0
  [ -n "$REPOTIC_CWD" ] || return 0
  repotic_resolve_actor_repo
  repotic_make_session_id
  repotic_call_stop_rpc
}
