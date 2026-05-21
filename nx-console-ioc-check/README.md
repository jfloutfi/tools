# Nx Console IOC Checker

A read-only macOS diagnostic script that scans the local machine for indicators of compromise (IOCs) associated with the malicious **Nx Console `18.95.0`** VS Code extension distributed via the `nrwl.angular-console` publisher.

The script does not modify, delete, or quarantine anything. It only reads files, queries running processes, and inspects logs, then prints `[OK]`, `[CHECK]`, or `[FOUND]` for each probe. A single `[FOUND]` will cause the script to exit with status `1` at the end.

## Background

In late 2025 a tampered build of the Nx Console extension (commit `558b09d7ad0d1660e2a0fb8a06da81a6f42e06d2`) was published under version `18.95.0`. On activation it dropped a secondary payload (`nx-next`) which targeted developer secrets, the AWS Instance Metadata Service, ECS task credentials, local Vault instances, and the `~/.claude/settings.json` file. It also wrote a persistence LaunchAgent (`com.user.kitty-monitor.plist`) and staged code under `/tmp/kitty-*` and `~/.local/share/kitty/cat.py`.

This script consolidates the known IOCs for that incident into one self-contained check.

## Usage

```bash
./check-nx-console-ioc.sh
```

For the most thorough scan (full sudoers inspection and complete unified-log access), run it with elevated privileges:

```bash
sudo ./check-nx-console-ioc.sh
```

Granting Terminal **Full Disk Access** in *System Settings → Privacy & Security* improves unified-log coverage in section 7.

### Exit codes

| Code | Meaning |
|------|---------|
| `0`  | No known IOCs found |
| `1`  | At least one IOC matched — treat the machine as potentially compromised |

### Output legend

| Tag | Meaning |
|-----|---------|
| `[OK]`    | Probe ran and found nothing suspicious |
| `[CHECK]` | Probe could not run completely (missing tool, missing path, insufficient permissions) — manual review may be warranted |
| `[FOUND]` | A known IOC matched |

## What is checked

The script runs twelve numbered sections. Each is independent — a failure in one does not abort the others.

### 1. Editor extension version

Enumerates installed extensions in VS Code, VS Code Insiders, Cursor, and Windsurf via their CLIs (`code`, `code-insiders`, `cursor`, `windsurf`) and by scanning each editor's `extensions/` directory. Flags any `nrwl.angular-console` folder or listing pinned to version `18.95.0`.

### 2. Editor logs

Greps the log directories of all four supported editors under `~/Library/Application Support/<Editor>/logs` for the malicious commit SHA, the GitHub install URL `github:nrwl/nx#558b09d7`, the function name `install-mcp-extension`, the C2 string `firedalazer`, and the version tag `@18.95.0`.

### 3. Known filesystem IOCs

Checks for the presence of:
- `~/.local/share/kitty/cat.py` — second-stage payload
- `~/Library/LaunchAgents/com.user.kitty-monitor.plist` — persistence agent
- `/var/tmp/.gh_update_state` — state file dropped by the payload
- `/tmp/kitty-*` and `/private/tmp/kitty-*` — staging directories

### 4. Running processes and environment

Runs `ps aux` and `ps eww` to detect the payload while it is live, and looks for the marker environment variables `__DAEMONIZED=1` and `NX_CONSOLE=true` on processes owned by the current user.

### 5. LaunchAgent state

Queries `launchctl list` for any loaded service whose label contains `kitty`, and scans both `~/Library/LaunchAgents` and `/Library/LaunchAgents` for on-disk plists referencing the same.

### 6. Package manager caches and shell history

Greps these locations for IOC strings and for the dropper package name `nx-next`:
- npm: `~/.npm`
- pnpm: `~/Library/pnpm`, `~/.local/share/pnpm`, `~/.pnpm-store`
- Bun: `~/.bun`
- Yarn: `~/Library/Caches/Yarn`, `~/.yarn/berry/cache`
- Homebrew global Node modules: `/opt/homebrew/lib/node_modules`, `/usr/local/lib/node_modules`
- nvm: every `~/.nvm/versions/node/*/lib/node_modules`
- Shell history: `~/.zsh_history`, `~/.bash_history`, `~/.local/share/fish/fish_history`

> Project-local `node_modules` directories are **not** scanned. Under pnpm they resolve into the global store (which *is* scanned). Under npm/yarn you must scan suspect project trees by hand.

### 7. macOS unified logs (last 14 days)

Runs `log show --last 14d` filtered by the IOC predicates. This step is slow and benefits significantly from Terminal Full Disk Access. Absence of hits here is weaker evidence than the on-disk checks above.

### 8. Network IOCs

- Uses `lsof -nP -i` to detect *active* connections to the credential-theft endpoints `169.254.169.254` (AWS IMDS), `169.254.170.2` (ECS task metadata), and `127.0.0.1:8200` (local Vault).
- Greps `/etc/hosts` for IOC patterns.
- If Little Snitch or LuLu is installed, scans their data directories for historical log entries.

> macOS does not keep a persistent network-flow log by default, so a clean result here only rules out *currently running* exfiltration unless a host firewall was logging at the time.

### 9. VS Code globalState marker

The payload writes the key `nxConsole.mcpExtensionInstalledSha=558b09d7…` into the editor's `state.vscdb` SQLite database. This marker survives extension uninstall, so it is a reliable forensic anchor. The script queries each editor's `state.vscdb` (using `sqlite3` when available, falling back to a binary grep otherwise).

### 10. Malicious file hash verification

For every `nrwl.angular-console*` extension folder it finds, the script computes `sha256` of `main.js`, `index.js`, and `package.json` and compares against the published known-bad hashes:

| Hash | File |
|------|------|
| `b0cefb66b953e5184b6adb3035e9e267335ac5eabfe1848e07834777b9397b74` | `main.js` |
| `e7347d90653efc565f03733a95e9209d78f9cfa81e31ff2b2dd9d48d75a4b8b1` | `index.js` (obfuscated payload) |
| `1a4afce34918bdc74ae3f31edaffffaa0ee074d83618f53edfd88137927340b8` | VSIX v18.95.0 |
| `43f2b001846c4966073ebffa5be8f15e491a1e7d32bbd805d57406ff540e0dd9` | dropper `package.json` |

It also walks `~/Downloads`, `~/Desktop`, `/tmp`, and `/private/tmp` (up to two levels deep) hashing any `.vsix` files to catch manually sideloaded copies.

### 11. Sudoers tampering

Prints the modification time of `/etc/sudoers` and `/etc/sudoers.d/` and — when run with passwordless sudo or as root — greps for `NOPASSWD` entries. Some `NOPASSWD` rules are legitimate (Homebrew, MDM), so this is a `[CHECK]` rather than a `[FOUND]`.

### 12. Claude / MCP config scan

The campaign specifically read `~/.claude/settings.json` for tokens. This section scans the following for IOC strings (`mcpExtensionInstalledSha`, `nx-next`, and the core IOC pattern):

- `~/.claude/settings.json`
- `~/.claude/settings.local.json`
- `~/Library/Application Support/Claude/claude_desktop_config.json`

## Interpreting the result

- **All `[OK]`** — none of the known IOCs are present. This does *not* prove the machine is uncompromised, only that this incident's signatures are absent.
- **One or more `[FOUND]`** — assume compromise. Rotate credentials from the affected machine (cloud, npm, GitHub, Anthropic, etc.), revoke active sessions, and begin incident response before doing anything else on the host.
- **`[CHECK]` warnings** — review manually. Most commonly these indicate a missing optional tool (`lsof`, `sqlite3`) or a directory that simply does not exist on this machine.

## Requirements

- macOS (paths and `log show` predicates are macOS-specific)
- `bash` 3.2+ (the default `/usr/bin/env bash` on macOS)
- Optional but recommended: `sqlite3`, `lsof`, `shasum`, passwordless `sudo`, and Terminal Full Disk Access

## Safety

The script uses `set -u` and `set -o pipefail` but performs no writes. Every probe uses read-only commands (`grep`, `find`, `ls`, `stat`, `ps`, `launchctl list`, `lsof`, `log show`, `sqlite3 SELECT`, `shasum`). It is safe to run repeatedly.
