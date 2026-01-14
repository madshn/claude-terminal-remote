# TODO / Issues List

Last updated: 2026-01-14

## Active Issues

### High Priority

- [ ] **VSCode Terminal Targeting**
  - Current: Keystrokes go to frontmost VSCode terminal
  - Desired: Target specific integrated terminal by TTY
  - Blocker: VSCode doesn't expose terminal-to-TTY mapping via AppleScript
  - Explore: VSCode extension API, or accept limitation

### Medium Priority

- [ ] **Outdated Message Clearing**
  - When new notification arrives for same TTY, old ones should be dismissed
  - Options:
    a. Use ntfy's `clear=true` more aggressively
    b. Track message IDs and clear via API
    c. Use topic-per-TTY (complicates subscription)
  - Decision needed on approach

- [ ] **ntfy iOS Native Actions** (upstream)
  - Issue filed: https://github.com/binwiederhier/ntfy/issues/1546
  - Waiting on ntfy-ios to implement `UNNotificationCategory`
  - Would enable: swipe actions, Apple Watch buttons

### Low Priority

- [ ] **README Update**
  - Document new single-topic format (`clauderemote-{SECRET}`)
  - Add VSCode support section
  - Update architecture diagram

- [ ] **Error Handling**
  - Poller should handle Supabase connectivity issues gracefully
  - Add retry logic with backoff
  - Surface errors to user somehow (notification?)

## Completed

- [x] Notification delay with activity detection
- [x] Tool context in notification messages
- [x] VSCode support in poller (TTY detection + keystroke routing)
- [x] Single topic convention
- [x] Filed ntfy-ios feature request (#1546)

## Research / Exploration

### Next Session: Evaluate Tools & Libraries

Use **Context7 MCP** to explore better tools for this tech domain:

1. **AppleScript/macOS Automation**
   - Query: "macOS automation scripting terminal control"
   - Look for: JXA (JavaScript for Automation), Hammerspoon, or other tools
   - Goal: More reliable terminal targeting

2. **VSCode Extension Development**
   - Query: "vscode extension terminal API"
   - Look for: How to map integrated terminals to TTYs
   - Goal: Enable targeted keystroke injection

3. **Push Notification Services**
   - Query: "push notification service with action buttons iOS"
   - Look for: Alternatives to ntfy with better iOS action support
   - Consider: Pushover, Pushcut, custom APNs

4. **Shell Process Management**
   - Query: "bash process management TTY detection"
   - Look for: Better patterns for process tree walking
   - Goal: More robust TTY-to-app detection

5. **n8n Workflow Patterns**
   - Query: "n8n webhook workflow patterns"
   - Look for: Best practices for webhook -> queue -> action flows
   - Goal: Optimize the signal routing workflow

### Commands to Run Next Session

```
# In Claude Code, use Context7 MCP:
mcp__plugin_context7_context7__resolve-library-id
mcp__plugin_context7_context7__query-docs
```

Example queries:
- "How to control VSCode integrated terminal programmatically"
- "macOS send keystroke to specific application window"
- "iOS notification action buttons UNNotificationCategory"
