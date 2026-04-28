#!/usr/bin/env bash
# Map a working directory to a rightaim.team actor name.
# Sourced by repotic-session-start.sh and repotic-session-stop.sh.
# Updating the map = edit this single file in master source; clients pick it up via repotic-update.
#
# === SWAP POINT (v2 / multi-principal, multi-machine) ===
# This case-statement is intentionally hardcoded to /Users/madsnissen/ for v1.
# v1 reality: one principal, one machine; the win here is "one migration site
# instead of 18 forked hook copies", not "no hardcoded paths".
#
# When multi-principal or multi-machine support arrives, replace the body of
# repotic_actor_for_cwd() with an RPC call to a Supabase function that resolves
# (host_id, cwd) → actor against a server-side mapping. Hooks should fall back
# to "unknown" on RPC failure so registration still happens.
# See repotic issue #90 for the trust/auth story that needs to land first.
# === END SWAP POINT ===

repotic_actor_for_cwd() {
  local cwd="$1"
  local actor="unknown"
  case "$cwd" in
    # team
    /Users/madsnissen/team/principal*)       actor="mads" ;;
    /Users/madsnissen/team/bob*)             actor="bob" ;;
    /Users/madsnissen/team/mira*)            actor="mira" ;;
    /Users/madsnissen/team/aston*)           actor="aston" ;;
    /Users/madsnissen/team/rex*)             actor="rex" ;;
    /Users/madsnissen/team/metrick*)         actor="metrick" ;;
    /Users/madsnissen/team/leah*)            actor="leah" ;;
    # ops
    /Users/madsnissen/ops/cloud-agent-host*) actor="cah" ;;
    /Users/madsnissen/ops/file-kiosk*)       actor="kiosk" ;;
    /Users/madsnissen/ops/python-worker*)    actor="pyworker" ;;
    /Users/madsnissen/ops/rightaim-ai*)      actor="raw" ;;
    /Users/madsnissen/ops/walkietalkieweb*)  actor="wtw" ;;
    /Users/madsnissen/ops/repotic*)          actor="repotic" ;;
    # builds
    /Users/madsnissen/builds/localpush*)       actor="lpush" ;;
    /Users/madsnissen/builds/preloadedyear*)   actor="ply" ;;
    /Users/madsnissen/builds/spawnby*)         actor="spawn" ;;
    /Users/madsnissen/builds/mdm*)             actor="mdm" ;;
    /Users/madsnissen/builds/yahboom*)         actor="yahboom" ;;
    /Users/madsnissen/builds/pogo*)            actor="pogo" ;;
    /Users/madsnissen/builds/ownbrain*)        actor="ownbrain" ;;
  esac
  printf '%s' "$actor"
}
