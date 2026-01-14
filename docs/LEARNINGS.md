# Learnings Summary

Session: 2026-01-14

## Technical Discoveries

### 1. Bash Loop Iteration with Newline-Separated Output

**Problem:** Using `for pid in $pids` where `$pids` contains newline-separated values doesn't iterate correctly - it treats all values as one string.

**Solution:** Use `while IFS= read -r` with process substitution:
```bash
# Bad
local pids=$(lsof -t "/dev/${tty_name}" 2>/dev/null)
for pid in $pids; do ...

# Good
while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    ...
done < <(lsof -t "/dev/${tty_name}" 2>/dev/null)
```

### 2. Process Name Truncation in `ps`

**Problem:** `ps -o comm=` truncates process names (e.g., "Visual Studio Code" becomes "Code Helper").

**Solution:** Use `ps -o command=` for full command path, which includes the full application name.

### 3. TTY Detection for Terminal Apps

**Approach:** Walk the process tree from TTY-owning PIDs up to parents to find the owning application:
```bash
lsof -t "/dev/ttys001"  # Get PIDs using the TTY
ps -o ppid= -p $pid     # Get parent PID
ps -o command= -p $pid  # Get full command to check app name
```

**Key patterns for VSCode detection:**
- `"Visual Studio Code"`
- `"Code.app"`
- `"/Electron"`

### 4. AppleScript for Keystroke Injection

**Terminal.app:** Can target specific tabs by TTY path
```applescript
repeat with t in tabs of w
    if tty of t is "/dev/ttys001" then ...
```

**VSCode:** Cannot target specific terminals - must activate the app and send to focused terminal
```applescript
tell application "Code" to activate
delay 0.3
tell application "System Events" to tell process "Code"
    keystroke "y"
    keystroke return
end tell
```

### 5. Claude Code Hooks

- Hooks run as subprocesses, so `tty` command returns "not a tty"
- Get TTY from parent process: `ps -o tty= -p $PPID`
- Transcript path available in hook JSON for extracting tool context
- `notification_type` distinguishes `permission_prompt` vs `idle_prompt`

### 6. ntfy.sh Capabilities

- Action buttons use HTTP callbacks with `clear=true` to dismiss
- Topic format: `https://ntfy.sh/{topic-name}`
- Actions header format: `http, Label, URL, method=POST, clear=true`
- iOS app has bugs with action button rendering in notification center
- Apple Watch support requires `UNNotificationCategory` registration (not implemented)

### 7. Frontmost App Detection (macOS)

```bash
osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true'
```
Returns: "Terminal", "Code", "Safari", etc.

## Architecture Insights

### Message Flow
```
Claude Code Hook → ntfy.sh → iOS/Watch notification
                           → User taps action button
                           → n8n webhook
                           → Supabase signal queue
                           → Local poller
                           → AppleScript keystroke
                           → Terminal/VSCode
```

### Single Topic vs Per-Project Topics

Initially used per-project topics (`{project}-ctr-{secret}`) but simplified to single topic (`clauderemote-{secret}`) because:
- User only needs to subscribe once in ntfy app
- TTY routing handles multi-project scenarios
- Simpler mental model

## What Worked Well

1. Notification delay with activity check - avoids spam when user is active
2. Tool context extraction from transcript - notifications show what's actually being asked
3. TTY-based routing - keystrokes go to correct terminal even with multiple projects

## What Needs More Work

1. VSCode terminal targeting - can only send to frontmost, not specific integrated terminal
2. iOS notification action buttons - require ntfy-ios changes (issue #1546)
3. Outdated message clearing - need strategy for dismissing stale notifications
