---
description: "Validate this repo's repotic client install matches the canonical pack and the lint rules from #88. Use when the user says 'check repotic', or when bob sweeps the fleet to verify every repo is correctly instrumented."
---

# repotic-check

Verify that this repo's repotic client assets are correctly installed and configured. Two failure modes get caught: **drift** (file out of date vs. manifest) and **misconfig** (settings.json wired wrong, paths point at the wrong repo, etc.).

## Trigger

- `repotic-check` / "check repotic" / "is repotic set up here?"
- Bob's fleet sweep — runs this in every known repo and aggregates results

## Validation rules

For each rule, report PASS / FAIL / WARN. Fail-class violations should produce non-zero exit so this can gate CI.

### Rule 1: Manifest parity (drift)

For every file in the master manifest, the local file at every `dest_path` must exist and sha256-match the manifest. Source of truth: `gh api repos/madshn/repotic/contents/client-repo-install/manifest.json`.

- **FAIL** if any required file is missing
- **FAIL** if any local sha256 differs from manifest sha256
- Auto-fix: invoke `repotic-update`

### Rule 2: Settings hook paths resolve under this repo

Every command path under hook entries in **both** `.claude/settings.json:hooks.{SessionStart,Stop}` and `.codex/hooks.json:hooks.{SessionStart,Stop}` must:

- Be an absolute path
- Start with the current repo's root (`git rev-parse --show-toplevel`)
- Point at a file under `.claude/hooks/` (Claude) or `.codex/hooks/` (Codex) that exists

This is the #88 bug: 7 repos had `settings.json` pointing at `/Users/madsnissen/test-installs/vps-cah-simulation/...` instead of their own `.claude/hooks/`. The same risk applies to Codex.

- **FAIL** if any hook command path doesn't start with this repo's root
- **FAIL** if the referenced script doesn't exist
- Auto-fix: invoke `repotic-update` (re-applies the settings fragment with correct `__REPO_ROOT__` substitution)

### Rule 3: Hooks live under the `hooks` key, not at JSON root

`SessionStart`, `Stop`, `PostToolUse`, etc. must live under the `hooks` object in both `.claude/settings.json` and `.codex/hooks.json`. A top-level `SessionStart` key (sibling of `hooks`) is silently ignored.

This is the second #88 bug: an automated rewrite placed `SessionStart` at the root.

- **WARN** if any hook event name appears as a top-level key in either settings file

### Rule 4: No legacy hook names

The legacy names `register-session.sh`, `deregister-session.sh`, and `register-local-session.sh` should not appear in any settings file or hook directory. They were renamed/replaced in the 2026-04-24 cleanup and the 2026-04-28 multi-runtime work.

- **WARN** if found

### Rule 5: Codex `codex_hooks` feature flag is enabled

For Codex hooks to fire at all, the `codex_hooks` feature must be enabled. Without it, the SessionStart hook script exists but never runs and Codex sessions silently fail to register on the bus.

Check via either of:

- `~/.codex/config.toml` contains `[features]` section with `codex_hooks = true`
- `codex features list` reports `codex_hooks: enabled`

- **FAIL** if the feature is disabled or unknown
- **Remediation:** `codex features enable codex_hooks` — but this skill does **not** run it. `repotic-check` is read-only by contract; mutation belongs to `repotic-update`. Report the disabled state with the exact command; the operator (or `repotic-update` on its next run) flips the flag.

### Rule 6: Codex hook wiring complete

In addition to drift/path validation (Rules 1–2):

- `.codex/hooks/repotic-session-start.sh` exists and is referenced from `.codex/hooks.json:hooks.SessionStart`
- `.codex/hooks/repotic-session-stop.sh` exists and is referenced from `.codex/hooks.json:hooks.Stop` (alongside any other Stop entries — array-merge, not exclusive)
- `.codex/hooks/register.sh` and `.codex/hooks/actor-map.sh` exist (sourced by both hook entry scripts)

- **FAIL** if any of the four files is missing
- **FAIL** if `.codex/hooks.json` doesn't reference the start/stop scripts under their respective events
- Auto-fix: invoke `repotic-update`

---

## Fix policy — present findings, ask the invoking agent

The skill never auto-fixes silently. After running all rules, it presents a complete findings summary and asks the **invoking agent** (whether a human-driven Claude session or bob during a fleet sweep) which violations to fix. The agent decides per its own judgment — a human user can hand-pick; bob can apply its own fleet-wide policy.

This avoids the "intentional local divergence vs. drift" ambiguity by deferring it to whoever is in the seat. The skill's job is to surface truth clearly, not to act unilaterally.

### Findings format

Present violations grouped by rule, with each violation tagged with a fix action. Then prompt.

```
repotic-check found 3 violations in ~/builds/localpush:

  [1] drift           .claude/hooks/actor-map.sh
                       local sha=a1b2... manifest sha=c3d4...
                       fix: invoke repotic-update

  [2] wrong-path      .claude/settings.json:hooks.SessionStart[0].command
                       value: /Users/madsnissen/test-installs/vps-cah-simulation/...
                       expected to start with: /Users/madsnissen/builds/localpush/
                       fix: invoke repotic-update (re-substitutes __REPO_ROOT__)

  [3] misplaced-key   .claude/settings.json
                       top-level "SessionStart" sibling of "hooks" — silently ignored by Claude Code
                       fix: manual JSON edit required (move under "hooks", remove top-level)

Apply fixes? Choose:
  (a) all auto-fixable [1, 2]
  (n) none — print and exit
  (i) interactive — ask per violation
  (or list specific numbers, e.g. "1 3")
```

### Implementation outline

```bash
report_and_prompt() {
  local violations_json="$1"   # array of {rule, target, detail, fix_kind}
  format_findings "$violations_json"   # the human-readable block above
  if [ -t 0 ]; then
    read -r -p "Apply fixes? [a/n/i/numbers]: " choice
    apply_choice "$choice" "$violations_json"
  else
    # non-interactive (e.g. CI): print findings and exit non-zero on any FAIL
    [ "$(jq '[.[] | select(.severity=="fail")] | length' <<<"$violations_json")" -eq 0 ]
  fi
}
```

For bob's fleet sweep, bob is the "invoking agent" reading the findings — bob applies its own policy by responding to the prompt the skill prints.

---

## Process

### Step 1: Identify the repo

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
```

### Step 2: Run all rules in order

Report each rule's outcome.

### Step 3: If any fixable violations, prompt OR apply

- Interactive (default): print the violations, ask "apply auto-fixes? [y/n]"
- Headless mode (`--auto-fix` flag, used by bob's fleet sweep): apply without prompting

### Step 4: Final report

Machine-readable summary suitable for bob to aggregate across the fleet:

```
repo: ~/builds/localpush
status: pass | fail
violations:
  - { rule: drift, file: .claude/hooks/actor-map.sh, fixed: true }
  - { rule: misplaced-key, key: .SessionStart, fixed: false }
```

---

## Reference

- Issue #88: lint validations the fleet-rename surfaced
- Issue #90: canonical asset ownership
- Master manifest: `madshn/repotic:client-repo-install/manifest.json`
