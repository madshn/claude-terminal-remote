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
TOPIC_SUFFIX="${CLAUDE_TERMINAL_TOPIC_SUFFIX:-}"
WEBHOOK_URL="${CLAUDE_TERMINAL_WEBHOOK_URL:-}"

# Source env file if it exists
if [ -f "$HOME/.claude-terminal-remote.env" ]; then
  source "$HOME/.claude-terminal-remote.env"
fi

# Generate a random topic suffix if not set (first run)
if [ -z "$TOPIC_SUFFIX" ]; then
  TOPIC_SUFFIX=$(openssl rand -hex 4)
  echo "Warning: CLAUDE_TERMINAL_TOPIC_SUFFIX not set. Using random: $TOPIC_SUFFIX" >&2
  echo "Add to ~/.claude-terminal-remote.env: CLAUDE_TERMINAL_TOPIC_SUFFIX=$TOPIC_SUFFIX" >&2
fi

# Read JSON input from Claude Code
input=$(cat)

# Log full input for debugging (uncomment when needed)
# echo "$input" >> /tmp/claude-hook-debug.log

# Capture TTY for routing keystrokes back to correct terminal
TTY_DEVICE=$(tty 2>/dev/null | sed 's|/dev/||')  # e.g., "ttys001"

# Extract fields
hook_event=$(echo "$input" | jq -r '.hook_event_name // "Unknown"')
message=$(echo "$input" | jq -r '.message // "Claude needs attention"')
notification_type=$(echo "$input" | jq -r '.notification_type // "default"')
cwd=$(echo "$input" | jq -r '.cwd // ""')
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')

# For permission prompts, extract tool description from transcript
tool_description=""
if [[ "$notification_type" == "permission_prompt" && -f "$transcript_path" ]]; then
  # Get the last tool_use entry's description from the transcript
  tool_description=$(tail -20 "$transcript_path" 2>/dev/null | \
    jq -r 'select(.message.content) | .message.content[] | select(.type == "tool_use") | .input.description // empty' 2>/dev/null | \
    tail -1)
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

# Build message body with project context and tool description
if [[ -n "$tool_description" ]]; then
  body="${tool_description} [${project}]"
else
  body="${message} [${project}]"
fi

# Build curl command
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

exit 0
