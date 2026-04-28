---
description: "Pull the latest repotic client assets (hooks, actor-map, settings fragment) from the master source. Use when the user says 'update repotic' or after a fleet-wide change to the canonical pack lands in ops/repotic/client-repo-install/."
---

# repotic-update

Sync this repo's repotic client assets with the canonical pack at `madshn/repotic:client-repo-install/`.

## Trigger

- `repotic-update` / `update repotic` / "pull latest repotic hooks"
- Invoked by `repotic-check` when it detects out-of-date assets

## What this skill does

For each entry in the master `manifest.json`, it:

1. Computes the local sha256 (if the file exists at any of `dest_paths`)
2. Compares against the manifest's expected sha256
3. If they differ → applies update policy (see TODO below)
4. For `settings_merges`: merges the fragment into the target settings file, substituting `__REPO_ROOT__` with the absolute path of the current repo root

---

## Process

### Step 1: Locate this repo's root

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
```

If not in a git repo, stop and report.

### Step 2: Fetch the manifest

```bash
gh api repos/madshn/repotic/contents/client-repo-install/manifest.json \
  --jq '.content' | base64 -d > /tmp/repotic-manifest.json
```

Parse `version`, `files[]`, `settings_merges[]`.

### Step 3: For each file in manifest

For each `file` entry with `src`, `dest_paths`, `mode`, `sha256`:

  a. For each `dest_path`:
     - Compute `LOCAL_SHA = sha256(REPO_ROOT/dest_path)` (empty string if file missing)
     - If `LOCAL_SHA == file.sha256` → skip (up to date)
     - Else → apply update policy (Step 5)

### Step 4: For each settings merge

For each `settings_merges[]` entry with `target_file`, `fragment_src`, `owned_paths`, optional `array_merge_paths`:

  a. Fetch the fragment from master (same `gh api` pattern, base64-decoded)
  b. Apply `substitutions` (e.g., `__REPO_ROOT__` → `$REPO_ROOT`). The `{{...}}` form in a substitution value means "shell-execute this and use stdout."
  c. Read existing `REPO_ROOT/target_file` (or `{}` if missing)
  d. **Owned paths (overwrite):** for each path in `owned_paths`, replace the value at that JSON path in the target with the fragment's value. Repotic owns these paths; existing values get overwritten on each update.
  e. **Array-merge paths (additive):** for each entry in `array_merge_paths`, merge the fragment's array INTO the target's existing array at that path, deduplicating by `dedup_key`. This is for paths Repotic shares with other consumers — e.g., Codex's `.codex/hooks.json:hooks.Stop` already contains `reaction-hook.sh`; we add `repotic-session-stop.sh` alongside without removing it. Idempotent: re-running update doesn't duplicate.
  f. Write back, preserving JSON formatting (2-space indent)

Example `array_merge_paths` entry:

```json
{
  "path": "hooks.Stop",
  "dedup_key": "hooks[0].command"
}
```

Dedup logic: for each item in the fragment's array, look at the value at `dedup_key` (here, the first hook's command path). If any existing item in the target's array has the same value at the same key, skip; otherwise append.

### Step 5: Update policy — overwrite + diff to stderr

**Master always wins.** When `LOCAL_SHA != manifest.sha256`, the file is overwritten with the manifest version. Before writing, the differences between local and remote are printed to stderr so a human reading the run output can see what got replaced.

This trades a small risk (a hand-edit gets overwritten) for simplicity and unattended-safety. Anyone debugging a hook locally should commit their edit upstream into `client-repo-install/` rather than expecting it to survive `repotic-update`.

```bash
apply_update_policy() {
  local dest_path="$1" local_sha="$2" manifest_sha="$3" remote_content="$4" mode="$5"
  if [ -f "$dest_path" ] && [ "$local_sha" != "$manifest_sha" ]; then
    echo "repotic-update: replacing $dest_path (local sha=${local_sha:0:8} → manifest sha=${manifest_sha:0:8})" >&2
    diff -u "$dest_path" <(printf '%s' "$remote_content") >&2 || true
  fi
  mkdir -p "$(dirname "$dest_path")"
  printf '%s' "$remote_content" > "$dest_path"
  chmod "$mode" "$dest_path"
}
```

### Step 5b: Per-machine prereqs (Codex `codex_hooks` flag)

If the manifest installs any Codex hook (`dest_paths` containing `.codex/hooks/...`), ensure `codex_hooks` is enabled before declaring the install successful — without it the hooks.json file is parsed but no hook ever fires.

```bash
if codex features list 2>/dev/null | grep -q '^codex_hooks:[[:space:]]*enabled'; then
  : # already enabled
else
  codex features enable codex_hooks >&2
fi
```

This is the mutation half of the boundary `repotic-check` deliberately doesn't cross. Idempotent; safe to run on every update.

### Step 6: Report

Print a short summary:

```
repotic-update complete:
  ✓ 3 files in sync
  ↑ 1 file updated: .claude/hooks/actor-map.sh
  ⚠ 1 file local-edits-detected: .claude/hooks/repotic-session-start.sh (skipped per policy)
```

---

## Reference

- Master source: `https://github.com/madshn/repotic/tree/main/client-repo-install`
- Manifest schema: `client-repo-install/manifest.json`
- Issue: #90 (canonical asset ownership)
