#!/bin/bash
# Claude Terminal Remote - Poller
# Polls Supabase for continue signals from ntfy -> n8n
# Sends keystrokes to the correct Terminal tab via AppleScript (matched by TTY)
#
# Part of claude-terminal-remote
# An add-on for ntfy (https://ntfy.sh) by Philipp C. Heckel

# Configuration - set in ~/.claude-terminal-remote.env or as environment variables
SUPABASE_URL="${CLAUDE_TERMINAL_SUPABASE_URL:-}"
SUPABASE_KEY="${CLAUDE_TERMINAL_SUPABASE_KEY:-}"
POLL_INTERVAL="${CLAUDE_TERMINAL_POLL_INTERVAL:-5}"
LOG_FILE="${CLAUDE_TERMINAL_LOG_FILE:-$HOME/Library/Logs/claude-terminal-remote.log}"

# Source env file if it exists
if [ -f "$HOME/.claude-terminal-remote.env" ]; then
  source "$HOME/.claude-terminal-remote.env"
fi

# Validate required config
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_KEY" ]; then
  echo "Error: CLAUDE_TERMINAL_SUPABASE_URL and CLAUDE_TERMINAL_SUPABASE_KEY must be set" >&2
  echo "Set them in ~/.claude-terminal-remote.env or as environment variables" >&2
  exit 1
fi

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log "Poller started (with TTY routing)"

while true; do
  response=$(curl -s --max-time 10 \
    "${SUPABASE_URL}/rest/v1/claude_signals?select=id,action,tty&order=created_at.asc&limit=1" \
    -H "apikey: ${SUPABASE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_KEY}")

  if [[ "$response" != "[]" && "$response" != "" && "$response" != "null" ]]; then
    id=$(echo "$response" | jq -r '.[0].id' 2>/dev/null)
    action=$(echo "$response" | jq -r '.[0].action' 2>/dev/null)
    tty=$(echo "$response" | jq -r '.[0].tty // ""' 2>/dev/null)

    if [[ "$id" != "null" && "$id" != "" ]]; then
      log "Received: action='$action' tty='$tty'"

      # Build the TTY path for matching (e.g., "ttys001" -> "/dev/ttys001")
      tty_path="/dev/${tty}"

      # Handle special actions (Escape for decline)
      if [[ "$action" == "n" || "$action" == "esc" ]]; then
        osascript <<EOF 2>/dev/null
          tell application "Terminal"
            set targetTab to missing value
            set targetWindow to missing value

            -- Find tab by TTY
            repeat with w in windows
              repeat with t in tabs of w
                if tty of t is "${tty_path}" then
                  set targetTab to t
                  set targetWindow to w
                  exit repeat
                end if
              end repeat
              if targetTab is not missing value then exit repeat
            end repeat

            if targetTab is not missing value then
              -- Bring window to front and select the tab
              activate
              set index of targetWindow to 1
              set selected tab of targetWindow to targetTab
              delay 0.3

              -- Send Escape key
              tell application "System Events" to tell process "Terminal"
                key code 53
              end tell
            end if
          end tell
EOF
      else
        # Send keystroke + return for other actions (1, 2, y, etc)
        osascript <<EOF 2>/dev/null
          tell application "Terminal"
            set targetTab to missing value
            set targetWindow to missing value

            -- Find tab by TTY
            repeat with w in windows
              repeat with t in tabs of w
                if tty of t is "${tty_path}" then
                  set targetTab to t
                  set targetWindow to w
                  exit repeat
                end if
              end repeat
              if targetTab is not missing value then exit repeat
            end repeat

            if targetTab is not missing value then
              -- Bring window to front and select the tab
              activate
              set index of targetWindow to 1
              set selected tab of targetWindow to targetTab
              delay 0.3

              -- Send keystroke
              tell application "System Events" to tell process "Terminal"
                keystroke "${action}"
                keystroke return
              end tell
            end if
          end tell
EOF
      fi

      # Delete the processed signal
      curl -s --max-time 10 -X DELETE \
        "${SUPABASE_URL}/rest/v1/claude_signals?id=eq.${id}" \
        -H "apikey: ${SUPABASE_KEY}" \
        -H "Authorization: Bearer ${SUPABASE_KEY}" \
        > /dev/null

      log "Sent '$action' to Terminal (tty: $tty)"
    fi
  fi

  sleep "$POLL_INTERVAL"
done
