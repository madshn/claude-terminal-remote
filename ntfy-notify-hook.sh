#!/bin/bash
# Claude Terminal Remote - ntfy Notification Hook
# Sends push notifications via ntfy.sh with action buttons
#
# Part of claude-terminal-remote
# An add-on for ntfy (https://ntfy.sh) by Philipp C. Heckel
#
# Install: Copy to ~/.claude/hooks/ntfy-notify.sh
# Configure Claude Code hooks in settings.json

# Configuration - set in ~/.claude-terminal-remote.env or as environment variables
# TOPIC_SUFFIX: unique suffix for your ntfy topics (generate with: openssl rand -hex 4)
# WEBHOOK_URL: your n8n webhook URL for action button callbacks

# Source env file FIRST, then read variables
if [ -f "$HOME/.claude-terminal-remote.env" ]; then
  source "$HOME/.claude-terminal-remote.env"
fi

TOPIC_SUFFIX="${CLAUDE_TERMINAL_TOPIC_SUFFIX:-}"
WEBHOOK_URL="${CLAUDE_TERMINAL_WEBHOOK_URL:-}"
NOTIFY_DELAY="${CLAUDE_TERMINAL_NOTIFY_DELAY:-60}"  # Default 60 seconds

# Generate a random topic suffix if not set (first run)
if [ -z "$TOPIC_SUFFIX" ]; then
  TOPIC_SUFFIX=$(openssl rand -hex 4)
  echo "Warning: CLAUDE_TERMINAL_TOPIC_SUFFIX not set. Using random: $TOPIC_SUFFIX" >&2
  echo "Add to ~/.claude-terminal-remote.env: CLAUDE_TERMINAL_TOPIC_SUFFIX=$TOPIC_SUFFIX" >&2
fi

# Read JSON input from Claude Code
input=$(cat)

# Log full input for debugging
echo "$input" >> /tmp/claude-hook-debug.log
# Log process tree for TTY debugging
echo "PPID=$PPID TTY=$(ps -o tty= -p $PPID 2>/dev/null) GPID=$(ps -o ppid= -p $PPID 2>/dev/null) GTTY=$(ps -o tty= -p $(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' ') 2>/dev/null)" >> /tmp/claude-hook-debug.log

# Capture TTY for routing keystrokes back to correct terminal
# The hook runs as a subprocess, so `tty` returns "not a tty"
# Instead, get the TTY from the parent Claude process via ps
TTY_DEVICE=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
# Fallback: try grandparent if parent has no TTY
if [[ -z "$TTY_DEVICE" || "$TTY_DEVICE" == "??" ]]; then
  GRANDPARENT=$(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' ')
  TTY_DEVICE=$(ps -o tty= -p $GRANDPARENT 2>/dev/null | tr -d ' ')
fi
# Ensure we have a valid TTY device name (e.g., "ttys001")
[[ -z "$TTY_DEVICE" || "$TTY_DEVICE" == "??" ]] && TTY_DEVICE="unknown"

# Extract fields
hook_event=$(echo "$input" | jq -r '.hook_event_name // "Unknown"')
message=$(echo "$input" | jq -r '.message // "Claude needs attention"')
notification_type=$(echo "$input" | jq -r '.notification_type // "default"')
cwd=$(echo "$input" | jq -r '.cwd // ""')
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')

# Detect if this is an AskUserQuestion dialog vs a real permission prompt
is_input_dialog=false
if [[ "$message" == "Claude Code needs your attention" ]]; then
  is_input_dialog=true
fi

# For real permission prompts, extract tool description from transcript
tool_description=""
if [[ "$notification_type" == "permission_prompt" && "$is_input_dialog" == "false" && -f "$transcript_path" ]]; then
  # Get the last tool_use entry's description from the transcript
  tool_description=$(tail -20 "$transcript_path" 2>/dev/null | \
    jq -r 'select(.message.content) | .message.content[] | select(.type == "tool_use") | .input.description // empty' 2>/dev/null | \
    tail -1)
fi

# For input dialogs, try to extract question and options from transcript
input_question=""
option1_label=""
option2_label=""
option3_label=""
if [[ "$is_input_dialog" == "true" && -f "$transcript_path" ]]; then
  # Look for AskUserQuestion tool_use and extract the question and options
  # Use jq -c for compact single-line output so tail -1 works correctly
  ask_json=$(tail -50 "$transcript_path" 2>/dev/null | \
    jq -c 'select(.message.content) | .message.content[] | select(.type == "tool_use" and .name == "AskUserQuestion") | .input' 2>/dev/null | \
    tail -1)

  if [[ -n "$ask_json" ]]; then
    input_question=$(echo "$ask_json" | jq -r '.questions[0].question // empty' 2>/dev/null)
    # Extract option labels, filtering out "Type something" / "Other" options
    option1_label=$(echo "$ask_json" | jq -r '.questions[0].options[0].label // empty' 2>/dev/null)
    option2_label=$(echo "$ask_json" | jq -r '.questions[0].options[1].label // empty' 2>/dev/null)
    option3_label=$(echo "$ask_json" | jq -r '.questions[0].options[2].label // empty' 2>/dev/null)

    # Filter out free-text options (users will need to respond manually for those)
    [[ "$option1_label" == *"Type"* || "$option1_label" == *"Other"* ]] && option1_label=""
    [[ "$option2_label" == *"Type"* || "$option2_label" == *"Other"* ]] && option2_label=""
    [[ "$option3_label" == *"Type"* || "$option3_label" == *"Other"* ]] && option3_label=""

    # Remove commas from labels (they break ntfy action format)
    option1_label="${option1_label//,/}"
    option2_label="${option2_label//,/}"
    option3_label="${option3_label//,/}"
  fi
fi

# Derive project name from cwd
project=$(basename "$cwd" 2>/dev/null || echo "claude")

# Handle worktree paths: .trees/NNN-feature-name -> use parent project
if [[ "$cwd" == *"/.trees/"* ]]; then
  main_repo=$(echo "$cwd" | sed 's|/.trees/.*||')
  project=$(basename "$main_repo" 2>/dev/null || echo "claude")
fi

# Build topic: {project}-claude-{suffix}
NTFY_TOPIC="${project}-claude-${TOPIC_SUFFIX}"
NTFY_URL="https://ntfy.sh/${NTFY_TOPIC}"

# Determine title, priority, and action buttons based on notification type
title="Claude Code"
priority="default"
tags="robot"
actions=""

if [[ "$is_input_dialog" == "true" ]]; then
  # AskUserQuestion dialog - show labeled options
  title="Input Needed"
  priority="high"
  tags="question,robot"
  if [ -n "$WEBHOOK_URL" ]; then
    # Build actions dynamically based on available options
    actions=""
    if [[ -n "$option1_label" ]]; then
      actions="http, ${option1_label}, ${WEBHOOK_URL}?action=1&tty=${TTY_DEVICE}, method=POST, clear=true"
    fi
    if [[ -n "$option2_label" ]]; then
      [[ -n "$actions" ]] && actions="${actions}; "
      actions="${actions}http, ${option2_label}, ${WEBHOOK_URL}?action=2&tty=${TTY_DEVICE}, method=POST, clear=true"
    fi
    if [[ -n "$option3_label" ]]; then
      [[ -n "$actions" ]] && actions="${actions}; "
      actions="${actions}http, ${option3_label}, ${WEBHOOK_URL}?action=3&tty=${TTY_DEVICE}, method=POST, clear=true"
    fi
    # Fallback to numbered buttons if no labels extracted
    if [[ -z "$actions" ]]; then
      actions="http, 1, ${WEBHOOK_URL}?action=1&tty=${TTY_DEVICE}, method=POST, clear=true; http, 2, ${WEBHOOK_URL}?action=2&tty=${TTY_DEVICE}, method=POST, clear=true"
    fi
  fi
else
  case "$notification_type" in
    "permission_prompt")
      title="Permission Needed"
      priority="high"
      tags="warning,robot"
      if [ -n "$WEBHOOK_URL" ]; then
        # Three buttons: Yes, Yes to All, No
        actions="http, Yes, ${WEBHOOK_URL}?action=1&tty=${TTY_DEVICE}, method=POST, clear=true; http, All, ${WEBHOOK_URL}?action=2&tty=${TTY_DEVICE}, method=POST, clear=true; http, No, ${WEBHOOK_URL}?action=n&tty=${TTY_DEVICE}, method=POST, clear=true"
      fi
      ;;
    "idle_prompt")
      title="Waiting for Input"
      priority="default"
      tags="hourglass,robot"
      if [ -n "$WEBHOOK_URL" ]; then
        # Two buttons: Continue, Skip
        actions="http, Continue, ${WEBHOOK_URL}?action=y&tty=${TTY_DEVICE}, method=POST, clear=true; http, Skip, ${WEBHOOK_URL}?action=skip&tty=${TTY_DEVICE}, method=POST, clear=true"
      fi
      ;;
    *)
      title="Claude Code"
      priority="default"
      tags="robot"
      actions=""
      ;;
  esac
fi

# Build message body with project context
if [[ -n "$input_question" ]]; then
  # Input dialog - show the question
  body="${input_question} [${project}]"
elif [[ -n "$tool_description" ]]; then
  # Permission prompt - show tool description
  body="${tool_description} [${project}]"
else
  body="${message} [${project}]"
fi

# Send notification after delay (in background so hook returns immediately)
(
  if [ "$NOTIFY_DELAY" -gt 0 ] 2>/dev/null; then
    sleep "$NOTIFY_DELAY"
  fi

  if [ -n "$actions" ]; then
    curl -s -X POST \
      -H "Title: ${title}" \
      -H "Priority: ${priority}" \
      -H "Tags: ${tags}" \
      -H "Actions: ${actions}" \
      -d "$body" \
      "${NTFY_URL}" >/dev/null 2>&1
  else
    curl -s -X POST \
      -H "Title: ${title}" \
      -H "Priority: ${priority}" \
      -H "Tags: ${tags}" \
      -d "$body" \
      "${NTFY_URL}" >/dev/null 2>&1
  fi
) &

exit 0
