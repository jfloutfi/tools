#!/usr/bin/env bash
set -u
set -o pipefail

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

FOUND=0

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[CHECK]${NC} $1"; }
bad()  { echo -e "${RED}[FOUND]${NC} $1"; FOUND=1; }

SHA="558b09d7ad0d1660e2a0fb8a06da81a6f42e06d2"
BAD_VERSION="18.95.0"
# Patterns reused across log/cache/history greps
PATTERN_CORE="${SHA}|github:nrwl/nx#558b09d7|install-mcp-extension|firedalazer"

echo "Nx Console ${BAD_VERSION} macOS IOC checker"
echo "Read-only checks only. No files will be changed."
echo

echo "== 1. Editor extension version check =="
check_editor_cli() {
  local cli="$1"
  if ! command -v "$cli" >/dev/null 2>&1; then
    return 0
  fi
  local ext_line
  ext_line=$("$cli" --list-extensions --show-versions 2>/dev/null | grep -i "nrwl.angular-console" || true)
  if [ -z "$ext_line" ]; then
    ok "Nx Console not listed by '$cli'"
  elif echo "$ext_line" | grep -qE "@${BAD_VERSION}\$"; then
    bad "Compromised Nx Console ${BAD_VERSION} installed via '$cli'"
    echo "$ext_line"
  else
    ok "Nx Console installed via '$cli', not ${BAD_VERSION}: $ext_line"
  fi
}

for cli in code code-insiders cursor windsurf; do
  check_editor_cli "$cli"
done

for dir in \
  "$HOME/.vscode/extensions" \
  "$HOME/.vscode-insiders/extensions" \
  "$HOME/.vscode-server/extensions" \
  "$HOME/.cursor/extensions" \
  "$HOME/.windsurf/extensions"; do
  if [ -d "$dir" ]; then
    matches=$(find "$dir" -maxdepth 1 -type d -iname "nrwl.angular-console*" 2>/dev/null || true)
    if echo "$matches" | grep -q "${BAD_VERSION}"; then
      bad "Compromised extension folder found in $dir"
      echo "$matches"
    elif [ -n "$matches" ]; then
      ok "Nx Console folders found in $dir, none are ${BAD_VERSION}:"
      echo "$matches"
    else
      ok "No Nx Console folder in $dir"
    fi
  fi
done

echo
echo "== 2. Editor logs for malicious version / SHA =="
LOG_ROOTS=(
  "$HOME/Library/Application Support/Code/logs"
  "$HOME/Library/Application Support/Code - Insiders/logs"
  "$HOME/Library/Application Support/Cursor/logs"
  "$HOME/Library/Application Support/Windsurf/logs"
)

for LOG_ROOT in "${LOG_ROOTS[@]}"; do
  if [ -d "$LOG_ROOT" ]; then
    hits=$(grep -REn "${PATTERN_CORE}|@${BAD_VERSION}" "$LOG_ROOT" 2>/dev/null | head -50 || true)
    if [ -n "$hits" ]; then
      bad "Suspicious log entries found in $LOG_ROOT"
      echo "$hits"
    else
      ok "No suspicious log entries in $LOG_ROOT"
    fi
  else
    warn "Log folder not found: $LOG_ROOT"
  fi
done

echo
echo "== 3. Known macOS filesystem IOCs =="
paths=(
  "$HOME/.local/share/kitty/cat.py"
  "$HOME/Library/LaunchAgents/com.user.kitty-monitor.plist"
  "/var/tmp/.gh_update_state"
)

for p in "${paths[@]}"; do
  if [ -e "$p" ]; then
    bad "IOC exists: $p"
    ls -la "$p"
  else
    ok "Not found: $p"
  fi
done

staging=$( { ls -d /tmp/kitty-* 2>/dev/null; ls -d /private/tmp/kitty-* 2>/dev/null; } || true )
if [ -n "$staging" ]; then
  bad "Staging directories found:"
  echo "$staging" | while IFS= read -r line; do
    [ -n "$line" ] && ls -ld "$line"
  done
else
  ok "No /tmp/kitty-* or /private/tmp/kitty-* directories"
fi

echo
echo "== 4. Running process and environment IOCs =="
proc_hits=$(ps aux 2>/dev/null | grep -v grep | grep -E "cat\.py|/tmp/kitty-|/private/tmp/kitty-" || true)
if [ -n "$proc_hits" ]; then
  bad "Suspicious running process found"
  echo "$proc_hits"
else
  ok "No suspicious cat.py or kitty-* processes running"
fi

# macOS ps aux does not show env vars; ps eww shows env for processes you own.
env_hits=$(ps eww 2>/dev/null | grep -v grep | grep -E "__DAEMONIZED=1|NX_CONSOLE=true" || true)
if [ -n "$env_hits" ]; then
  bad "Suspicious environment variables on running processes (__DAEMONIZED=1 or NX_CONSOLE=true)"
  echo "$env_hits"
else
  ok "No __DAEMONIZED=1 or NX_CONSOLE=true env vars on user processes"
fi

echo
echo "== 5. LaunchAgent loaded state =="
launch_hits=$(launchctl list 2>/dev/null | grep -i "kitty" || true)
if [ -n "$launch_hits" ]; then
  bad "Suspicious LaunchAgent entry found"
  echo "$launch_hits"
else
  ok "No kitty LaunchAgent loaded"
fi

# Also check on-disk LaunchAgent plists (loaded or not)
agent_files=$(find "$HOME/Library/LaunchAgents" /Library/LaunchAgents -maxdepth 1 -type f -iname "*kitty*" 2>/dev/null || true)
if [ -n "$agent_files" ]; then
  bad "On-disk LaunchAgent plist references kitty:"
  echo "$agent_files"
else
  ok "No on-disk kitty LaunchAgent plists"
fi

echo
echo "== 6. Package manager caches / globals / shell history hints =="
echo "Note: project-local node_modules dirs aren't scanned directly. With pnpm they're symlinks into the pnpm store, whose contents are scanned below. With npm/yarn, scan suspect project trees separately if concerned."

# Collect npm cache, pnpm store+global, and nvm per-version global node_modules
PM_PATHS=()
[ -d "$HOME/.npm" ] && PM_PATHS+=("$HOME/.npm")
[ -d "$HOME/Library/pnpm" ] && PM_PATHS+=("$HOME/Library/pnpm")
[ -d "$HOME/.local/share/pnpm" ] && PM_PATHS+=("$HOME/.local/share/pnpm")
[ -d "$HOME/.pnpm-store" ] && PM_PATHS+=("$HOME/.pnpm-store")
# Bun cache (dropper depends on bun and may cache the package here)
[ -d "$HOME/.bun" ] && PM_PATHS+=("$HOME/.bun")
# Yarn cache
[ -d "$HOME/Library/Caches/Yarn" ] && PM_PATHS+=("$HOME/Library/Caches/Yarn")
[ -d "$HOME/.yarn/berry/cache" ] && PM_PATHS+=("$HOME/.yarn/berry/cache")
# Homebrew Node globals: /opt/homebrew on Apple Silicon, /usr/local on Intel (or legacy installs)
[ -d "/opt/homebrew/lib/node_modules" ] && PM_PATHS+=("/opt/homebrew/lib/node_modules")
[ -d "/usr/local/lib/node_modules" ] && PM_PATHS+=("/usr/local/lib/node_modules")
# nvm: globally installed npm packages live per-Node-version under ~/.nvm/versions/node/*/lib/node_modules
if [ -d "$HOME/.nvm/versions/node" ]; then
  while IFS= read -r -d '' nm; do
    PM_PATHS+=("$nm")
  done < <(find "$HOME/.nvm/versions/node" -mindepth 3 -maxdepth 3 -type d -name node_modules -print0 2>/dev/null)
fi

if [ "${#PM_PATHS[@]}" -eq 0 ]; then
  warn "No npm/pnpm/nvm package directories found"
else
  for pm in "${PM_PATHS[@]}"; do
    pm_hits=$(grep -REn "${PATTERN_CORE}" "$pm" 2>/dev/null | head -20 || true)
    if [ -n "$pm_hits" ]; then
      bad "Suspicious package manager reference found in $pm"
      echo "$pm_hits"
    else
      ok "No suspicious references in $pm"
    fi
    # Dropper package name 'nx-next' — quoted form ensures we hit a JSON key/value, not random substrings
    dropper_hits=$(grep -REn '"nx-next"' "$pm" 2>/dev/null | head -10 || true)
    if [ -n "$dropper_hits" ]; then
      bad "Dropper package name 'nx-next' present in $pm"
      echo "$dropper_hits"
    fi
  done
fi

for hist in \
  "$HOME/.zsh_history" \
  "$HOME/.bash_history" \
  "$HOME/.local/share/fish/fish_history"; do
  if [ -f "$hist" ]; then
    hist_hits=$(grep -iE "${PATTERN_CORE}|kitty-monitor|cat\.py" "$hist" 2>/dev/null || true)
    if [ -n "$hist_hits" ]; then
      bad "Suspicious shell history entry found in $hist"
      echo "$hist_hits"
    else
      ok "No suspicious entries in $hist"
    fi
  fi
done

echo
echo "== 7. Recent macOS unified logs, last 14 days =="
echo "This may take a bit and may require Terminal Full Disk Access for best results."
log_hits=$(log show --last 14d --style compact \
  --predicate 'eventMessage CONTAINS "kitty" OR eventMessage CONTAINS "558b09d7" OR eventMessage CONTAINS "nrwl/nx" OR eventMessage CONTAINS "install-mcp-extension" OR eventMessage CONTAINS "firedalazer" OR eventMessage CONTAINS "__DAEMONIZED" OR eventMessage CONTAINS "NX_CONSOLE"' \
  2>/dev/null | grep -iE "${PATTERN_CORE}|cat\.py|/tmp/kitty-|/private/tmp/kitty-|__DAEMONIZED|NX_CONSOLE=true" | head -50 || true)
if [ -n "$log_hits" ]; then
  bad "Suspicious unified log entries found"
  echo "$log_hits"
else
  ok "No suspicious unified log entries found"
fi

echo
echo "== 8. Network IOCs =="
echo "Note: macOS keeps no persistent network flow log by default. Active-connection checks only catch malware still running; absence here is weak evidence unless Little Snitch / LuLu was already logging."

if command -v lsof >/dev/null 2>&1; then
  net_hits=$(lsof -nP -i 2>/dev/null | grep -E "169\.254\.169\.254|169\.254\.170\.2|127\.0\.0\.1:8200" || true)
  if [ -n "$net_hits" ]; then
    bad "Active connection to credential-theft endpoint (AWS IMDS / ECS / local Vault)"
    echo "$net_hits"
  else
    ok "No active connections to 169.254.169.254, 169.254.170.2, or 127.0.0.1:8200"
  fi
else
  warn "lsof not available — cannot enumerate active connections"
fi

hosts_hits=$(grep -iE "${PATTERN_CORE}|firedalazer|kitty" /etc/hosts 2>/dev/null || true)
if [ -n "$hosts_hits" ]; then
  bad "Suspicious /etc/hosts entries"
  echo "$hosts_hits"
else
  ok "No suspicious entries in /etc/hosts"
fi

LS_PATHS=(
  "$HOME/Library/Application Support/Little Snitch"
  "/Library/Application Support/Objective Development/Little Snitch"
  "$HOME/Library/Logs/Little Snitch"
  "$HOME/Library/Application Support/LuLu"
  "/Library/Objective-See/LuLu"
)
ls_found=0
for lsp in "${LS_PATHS[@]}"; do
  if [ -d "$lsp" ]; then
    ls_found=1
    ls_hits=$(grep -REn "${PATTERN_CORE}|firedalazer" "$lsp" 2>/dev/null | head -20 || true)
    if [ -n "$ls_hits" ]; then
      bad "Host-firewall data references IOC patterns in $lsp"
      echo "$ls_hits"
    else
      ok "No IOC patterns in $lsp (note: binary SQLite logs may not grep cleanly)"
    fi
  fi
done
if [ "$ls_found" -eq 0 ]; then
  warn "No Little Snitch or LuLu installation detected — no host-firewall log to scan"
fi

echo
echo "== 9. VS Code globalState marker =="
echo "The payload sets nxConsole.mcpExtensionInstalledSha=${SHA} on successful execution. This marker persists even after the extension is uninstalled."

STATE_DBS=(
  "$HOME/Library/Application Support/Code/User/globalStorage/state.vscdb"
  "$HOME/Library/Application Support/Code - Insiders/User/globalStorage/state.vscdb"
  "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
  "$HOME/Library/Application Support/Windsurf/User/globalStorage/state.vscdb"
)

for db in "${STATE_DBS[@]}"; do
  if [ ! -f "$db" ]; then
    continue
  fi
  if command -v sqlite3 >/dev/null 2>&1; then
    rows=$(sqlite3 "$db" "SELECT key, substr(value, 1, 200) FROM ItemTable WHERE value LIKE '%${SHA}%' OR value LIKE '%mcpExtensionInstalledSha%' OR key LIKE '%nrwl.angular-console%';" 2>/dev/null || true)
    if echo "$rows" | grep -q "${SHA}\|mcpExtensionInstalledSha"; then
      bad "VS Code globalState contains compromise marker in $db"
      echo "$rows" | head -10
    elif [ -n "$rows" ]; then
      ok "Nx Console state present in $db but no compromise marker"
    else
      ok "No Nx Console / compromise marker rows in $db"
    fi
  else
    if grep -aq "${SHA}\|mcpExtensionInstalledSha" "$db" 2>/dev/null; then
      bad "Compromise marker string found in $db (sqlite3 not available — binary grep)"
    else
      ok "No compromise marker string in $db (binary grep)"
    fi
  fi
done

echo
echo "== 10. Malicious file hash verification =="
KNOWN_BAD_HASHES=(
  "b0cefb66b953e5184b6adb3035e9e267335ac5eabfe1848e07834777b9397b74"  # main.js
  "e7347d90653efc565f03733a95e9209d78f9cfa81e31ff2b2dd9d48d75a4b8b1"  # index.js (obfuscated payload)
  "1a4afce34918bdc74ae3f31edaffffaa0ee074d83618f53edfd88137927340b8"  # VSIX v18.95.0
  "43f2b001846c4966073ebffa5be8f15e491a1e7d32bbd805d57406ff540e0dd9"  # dropper package.json
)

EXT_DIRS=(
  "$HOME/.vscode/extensions"
  "$HOME/.vscode-insiders/extensions"
  "$HOME/.vscode-server/extensions"
  "$HOME/.cursor/extensions"
  "$HOME/.windsurf/extensions"
)

hash_checked=0
hash_matched=0
for ed in "${EXT_DIRS[@]}"; do
  [ -d "$ed" ] || continue
  while IFS= read -r -d '' folder; do
    while IFS= read -r -d '' f; do
      hash_checked=$((hash_checked + 1))
      h=$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}')
      for bad_hash in "${KNOWN_BAD_HASHES[@]}"; do
        if [ "$h" = "$bad_hash" ]; then
          bad "Known-malicious file hash matched: $f"
          echo "  sha256: $h"
          hash_matched=1
        fi
      done
    done < <(find "$folder" -type f \( -name "main.js" -o -name "index.js" -o -name "package.json" \) -print0 2>/dev/null)
  done < <(find "$ed" -maxdepth 1 -type d -iname "nrwl.angular-console*" -print0 2>/dev/null)
done

# Also hash any loose .vsix files in download / staging locations — catches manual sideload
VSIX_SCAN_DIRS=(
  "$HOME/Downloads"
  "$HOME/Desktop"
  "/tmp"
  "/private/tmp"
)
for vd in "${VSIX_SCAN_DIRS[@]}"; do
  [ -d "$vd" ] || continue
  while IFS= read -r -d '' f; do
    hash_checked=$((hash_checked + 1))
    h=$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}')
    for bad_hash in "${KNOWN_BAD_HASHES[@]}"; do
      if [ "$h" = "$bad_hash" ]; then
        bad "Known-malicious VSIX hash matched outside extension dirs: $f"
        echo "  sha256: $h"
        hash_matched=1
      fi
    done
  done < <(find "$vd" -maxdepth 2 -type f -name "*.vsix" -print0 2>/dev/null)
done

if [ "$hash_checked" -eq 0 ]; then
  ok "No Nx Console files to hash (no extension folders found)"
elif [ "$hash_matched" -eq 0 ]; then
  ok "Hashed ${hash_checked} candidate file(s); none matched the known-bad list"
fi

echo
echo "== 11. Sudoers tampering =="
if [ "$(id -u)" -ne 0 ]; then
  echo "Note: reading /etc/sudoers* requires root. Re-run as 'sudo $0' for full inspection."
fi

for f in /etc/sudoers /etc/sudoers.d; do
  if [ -e "$f" ]; then
    mtime=$(stat -f "%Sm" "$f" 2>/dev/null || echo "?")
    echo "  $f mtime: $mtime"
  fi
done

if sudo -n true 2>/dev/null; then
  sudo_hits=$(sudo grep -REn "NOPASSWD" /etc/sudoers /etc/sudoers.d 2>/dev/null || true)
  if [ -n "$sudo_hits" ]; then
    warn "NOPASSWD entries found — review for unexpected rules (Homebrew/MDM tools legitimately use NOPASSWD)"
    echo "$sudo_hits"
  else
    ok "No NOPASSWD entries in /etc/sudoers or /etc/sudoers.d/"
  fi
else
  warn "Passwordless sudo not available — cannot inspect /etc/sudoers* contents without prompting"
fi

echo
echo "== 12. Claude / MCP config IOC scan =="
echo "Article notes ~/.claude/settings.json is specifically targeted (read for tokens). Belt-and-suspenders check for IOC strings inside Claude/MCP configs."

MCP_PATHS=(
  "$HOME/.claude/settings.json"
  "$HOME/.claude/settings.local.json"
  "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
)

mcp_checked=0
mcp_matched=0
for p in "${MCP_PATHS[@]}"; do
  if [ -f "$p" ]; then
    mcp_checked=$((mcp_checked + 1))
    mcp_hits=$(grep -E "${PATTERN_CORE}|mcpExtensionInstalledSha|nx-next" "$p" 2>/dev/null || true)
    if [ -n "$mcp_hits" ]; then
      bad "IOC strings found in $p"
      echo "$mcp_hits"
      mcp_matched=1
    fi
  fi
done

if [ "$mcp_checked" -eq 0 ]; then
  ok "No Claude/MCP config files found"
elif [ "$mcp_matched" -eq 0 ]; then
  ok "Scanned ${mcp_checked} Claude/MCP config file(s); no IOC strings found"
fi

echo
echo "== Summary =="
if [ "$FOUND" -eq 1 ]; then
  echo -e "${RED}Potential IOC found. Treat this machine as potentially compromised until reviewed.${NC}"
  exit 1
else
  echo -e "${GREEN}No known Nx Console ${BAD_VERSION} IOCs found by this script.${NC}"
  echo "This does not prove perfect cleanliness, but it matches a low-risk result."
fi
