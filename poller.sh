#!/bin/bash
# Claude Terminal Remote - Poller
# Polls Supabase for continue signals from ntfy -> n8n
# Sends keystrokes to the correct terminal (Terminal.app or VSCode) via AppleScript
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

# Detect which app owns a TTY (Terminal or VSCode)
# Returns: "Terminal", "VSCode", or "unknown"
detect_tty_owner() {
  local tty_name="$1"

  # Get the processes using this TTY - use while read for proper line handling
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue

    # Check the process and its ancestors for VSCode
    local proc_info=$(ps -o command= -p "$pid" 2>/dev/null)
    if [[ "$proc_info" == *"Visual Studio Code"* ]] || [[ "$proc_info" == *"Code.app"* ]] || [[ "$proc_info" == *"/Electron"* ]]; then
      echo "VSCode"
      return
    fi

    # Check parent processes
    local ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    while [[ -n "$ppid" && "$ppid" != "1" && "$ppid" != "0" ]]; do
      proc_info=$(ps -o command= -p "$ppid" 2>/dev/null)
      if [[ "$proc_info" == *"Visual Studio Code"* ]] || [[ "$proc_info" == *"Code.app"* ]] || [[ "$proc_info" == *"/Electron"* ]]; then
        echo "VSCode"
        return
      fi
      ppid=$(ps -o ppid= -p "$ppid" 2>/dev/null | tr -d ' ')
    done
  done < <(lsof -t "/dev/${tty_name}" 2>/dev/null | head -5)

  # Default to Terminal if not VSCode
  echo "Terminal"
}

# Send keystroke to VSCode
send_to_vscode() {
  local action="$1"
  local is_escape="$2"

  if [[ "$is_escape" == "true" ]]; then
    osascript <<EOF 2>/dev/null
      tell application "Code" to activate
      delay 0.3
      tell application "System Events" to tell process "Code"
        key code 53
      end tell
EOF
  else
    osascript <<EOF 2>/dev/null
      tell application "Code" to activate
      delay 0.3
      tell application "System Events" to tell process "Code"
        keystroke "${action}"
        keystroke return
      end tell
EOF
  fi
}

# Send keystroke to Terminal.app (with TTY matching)
send_to_terminal() {
  local action="$1"
  local tty_path="$2"
  local is_escape="$3"

  if [[ "$is_escape" == "true" ]]; then
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
}

log "Poller started (with TTY routing, Terminal + VSCode support)"

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
      # Detect which app owns this TTY
      tty_owner=$(detect_tty_owner "$tty")
      log "Received: action='$action' tty='$tty' owner='$tty_owner'"

      # Build the TTY path for Terminal.app matching
      tty_path="/dev/${tty}"

      # Determine if this is an escape action
      is_escape="false"
      [[ "$action" == "n" || "$action" == "esc" ]] && is_escape="true"

      # Send to appropriate app
      if [[ "$tty_owner" == "VSCode" ]]; then
        send_to_vscode "$action" "$is_escape"
        log "Sent '$action' to VSCode (tty: $tty)"
      else
        send_to_terminal "$action" "$tty_path" "$is_escape"
        log "Sent '$action' to Terminal (tty: $tty)"
      fi

      # Delete the processed signal
      curl -s --max-time 10 -X DELETE \
        "${SUPABASE_URL}/rest/v1/claude_signals?id=eq.${id}" \
        -H "apikey: ${SUPABASE_KEY}" \
        -H "Authorization: Bearer ${SUPABASE_KEY}" \
        > /dev/null
    fi
  fi

  sleep "$POLL_INTERVAL"
done
