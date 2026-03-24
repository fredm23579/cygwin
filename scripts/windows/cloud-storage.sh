#!/usr/bin/env bash
# =============================================================================
# cloud-storage.sh — OneDrive / Google Drive / Dropbox helpers for Cygwin
# =============================================================================
#
# Cloud storage sync agents (OneDrive, Google Drive, Dropbox) can interfere
# with Cygwin builds:
#   - File-lock conflicts during compilation
#   - Excessive sync activity for large build artifact trees
#   - Corrupted object files if the sync agent writes mid-compile
#   - Slow builds on metered connections
#
# This script helps you:
#   1. Detect if your Cygwin installation or build tree is inside a sync folder
#   2. Add build directories to cloud storage exclusion lists
#   3. Find the correct Cygwin-accessible paths to synced folders
#   4. Show sync status from the command line
#
# Usage:
#   bash scripts/windows/cloud-storage.sh [COMMAND]
#
# Commands:
#   --check            Warn if repo/build is inside a synced folder (default)
#   --setup-excludes   Add build/ and install/ to OneDrive exclusions
#   --paths            Print Cygwin paths for common cloud storage roots
#   --status           Show OneDrive sync status (via PowerShell)
#   -h, --help         Show this help
#
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ── Colour helpers ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

ok()  { printf "${GREEN}[✓]${RESET} %s\n" "$*"; }
warn(){ printf "${YELLOW}[!]${RESET} %s\n" "$*"; }
err() { printf "${RED}[✗]${RESET} %s\n" "$*" >&2; }
log() { printf "${CYAN}[cloud]${RESET} %s\n" "$*"; }

# ── Windows path helpers ───────────────────────────────────────────────────────
win_env() {
  cmd.exe /c "echo %${1}%" 2>/dev/null | tr -d '\r\n' | xargs -I{} cygpath '{}' 2>/dev/null || echo ''
}

USERPROFILE=$(win_env USERPROFILE)
LOCALAPPDATA=$(win_env LOCALAPPDATA)
ONEDRIVE=$(win_env OneDrive || true)
ONEDRIVE_COMMERCIAL=$(win_env OneDriveCommercial || true)

# ── Find cloud storage roots ───────────────────────────────────────────────────
find_onedrive() {
  # OneDrive personal
  local candidates=(
    "${ONEDRIVE:-}"
    "${USERPROFILE}/OneDrive"
    "${LOCALAPPDATA}/Microsoft/OneDrive"
  )
  for d in "${candidates[@]}"; do
    [[ -d "$d" ]] && echo "$d" && return
  done
}

find_onedrive_business() {
  local candidates=(
    "${ONEDRIVE_COMMERCIAL:-}"
    "${USERPROFILE}/OneDrive - "*
  )
  for d in "${candidates[@]}"; do
    [[ -d "$d" ]] && echo "$d" && return
  done
}

find_google_drive() {
  # Google Drive Desktop mounts as a virtual drive with a letter that varies
  # per user. Rather than guessing letters, use a glob over all /cygdrive/?/
  # entries and look for the canonical "My Drive" directory.
  local p
  for p in /cygdrive/?/My\ Drive /cygdrive/?/MyDrive; do
    [[ -d "$p" ]] && echo "$p" && return
  done
  # Also check common user-directory locations (older Drive versions)
  for p in \
    "${USERPROFILE}/Google Drive" \
    "${USERPROFILE}/My Drive"; do
    [[ -d "$p" ]] && echo "$p" && return
  done
}

find_dropbox() {
  local info_file="${APPDATA:-${USERPROFILE}/AppData/Roaming}/Dropbox/info.json"
  if [[ -f "$info_file" ]]; then
    # Parse the Dropbox config file with explicit error handling so that a
    # malformed JSON doesn't produce a confusing Python traceback.
    local dropbox_win_path
    dropbox_win_path=$(python3 - "$info_file" 2>/dev/null <<'PYEOF'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    # info.json has shape: {"personal": {"path": "..."}, ...}
    path = next(iter(data.values()))["path"]
    print(path)
except Exception:
    sys.exit(1)
PYEOF
    ) || true
    if [[ -n "$dropbox_win_path" ]]; then
      cygpath "$dropbox_win_path" 2>/dev/null && return
    fi
  fi
  # Fallback: common locations
  [[ -d "${USERPROFILE}/Dropbox" ]] && echo "${USERPROFILE}/Dropbox"
}

# ── is_inside_synced_folder PATH ──────────────────────────────────────────────
# Returns 0 (true) if PATH is inside a known cloud sync directory.
is_inside_synced_folder() {
  local path; path=$(realpath "$1" 2>/dev/null || echo "$1")
  local synced_roots=()

  local od; od=$(find_onedrive 2>/dev/null || true)
  [[ -n "$od" ]] && synced_roots+=("$(realpath "$od" 2>/dev/null || echo "$od")")

  local odb; odb=$(find_onedrive_business 2>/dev/null || true)
  [[ -n "$odb" ]] && synced_roots+=("$(realpath "$odb" 2>/dev/null || echo "$odb")")

  local gd; gd=$(find_google_drive 2>/dev/null || true)
  [[ -n "$gd" ]] && synced_roots+=("$(realpath "$gd" 2>/dev/null || echo "$gd")")

  local db; db=$(find_dropbox 2>/dev/null || true)
  [[ -n "$db" ]] && synced_roots+=("$(realpath "$db" 2>/dev/null || echo "$db")")

  for root in "${synced_roots[@]}"; do
    [[ -n "$root" ]] && [[ "$path" == "${root}"* ]] && return 0
  done
  return 1
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_check() {
  log "Checking cloud storage conflicts for: ${REPO_ROOT}"
  echo ""

  local issues=0

  # Check the repo root itself
  if is_inside_synced_folder "$REPO_ROOT"; then
    warn "The repository is inside a cloud-synced folder!"
    warn "  Path: ${REPO_ROOT}"
    warn "  This can cause file-lock conflicts during builds."
    warn "  Recommendation: move the repo outside the sync boundary, or at"
    warn "  minimum add 'build/' and 'install/' to the exclusion list."
    warn "  Run: bash scripts/windows/cloud-storage.sh --setup-excludes"
    (( issues++ )) || true
  else
    ok "Repository is NOT inside a cloud-synced folder."
  fi

  # Check build/ directory separately (it may exist in a different location)
  if [[ -d "${REPO_ROOT}/build" ]] && is_inside_synced_folder "${REPO_ROOT}/build"; then
    warn "The build/ directory is inside a cloud-synced folder."
    warn "Consider using an out-of-tree build in a non-synced location."
    (( issues++ )) || true
  elif [[ -d "${REPO_ROOT}/build" ]]; then
    ok "build/ directory is NOT inside a cloud-synced folder."
  fi

  echo ""
  if (( issues == 0 )); then
    ok "No cloud storage conflicts detected."
  else
    warn "${issues} potential issue(s) detected. See recommendations above."
  fi
}

cmd_paths() {
  printf "\n${BOLD}Cloud storage paths accessible from Cygwin:${RESET}\n\n"

  local od; od=$(find_onedrive 2>/dev/null || true)
  printf "  %-28s %s\n" "OneDrive (personal):" "${od:-not found}"

  local odb; odb=$(find_onedrive_business 2>/dev/null || true)
  printf "  %-28s %s\n" "OneDrive (business/org):" "${odb:-not found}"

  local gd; gd=$(find_google_drive 2>/dev/null || true)
  printf "  %-28s %s\n" "Google Drive:" "${gd:-not found}"

  local db; db=$(find_dropbox 2>/dev/null || true)
  printf "  %-28s %s\n" "Dropbox:" "${db:-not found}"

  echo ""
  log "Use these paths in scripts when you need to read/write synced files."
  log "Example: cp myfile.txt '${od:-/path/to/OneDrive}/Documents/'"
}

cmd_setup_excludes() {
  log "Setting up OneDrive exclusions for build artifacts…"

  # OneDrive stores per-folder exclusion hints via desktop.ini and
  # the selective sync feature. The most reliable approach on modern
  # Windows 11 is to add the folders to OneDrive's "vault" exclusion
  # using PowerShell + the OneDrive COM API.
  #
  # For simplicity, we create an odignore-style marker file in build/
  # and print instructions for manual configuration.

  local build_dir="${REPO_ROOT}/build"
  local install_dir="${REPO_ROOT}/install"

  mkdir -p "$build_dir" "$install_dir"

  # Create a .gitignore-style README to remind future developers
  for dir in "$build_dir" "$install_dir"; do
    cat > "${dir}/.cloud-exclude-marker" <<MARKER
This directory contains build artifacts generated by the Cygwin build system.
It should NOT be synced to cloud storage (OneDrive, Google Drive, Dropbox).

To exclude from OneDrive sync:
  1. Right-click the folder in File Explorer
  2. OneDrive → "Always keep on this device" or choose to not sync

To exclude from Google Drive:
  - Move this directory outside the Google Drive folder

Build artifacts here may be very large (>1 GB) and change frequently,
making them unsuitable for cloud sync.
MARKER
    ok "Created exclusion marker in: ${dir}"
  done

  # Attempt to set the OneDrive "backup excluded" attribute via PowerShell
  local ps_script='
$buildPath = "' + (cygpath -w "$build_dir") + '"
$installPath = "' + (cygpath -w "$install_dir") + '"

foreach ($path in @($buildPath, $installPath)) {
  try {
    # Set the "not content indexed" attribute which hints to OneDrive
    $acl = Get-Item $path -Force
    $acl.Attributes = $acl.Attributes -bor [System.IO.FileAttributes]::NotContentIndexed
    Write-Host "Set NotContentIndexed on: $path"
  } catch {
    Write-Warning "Could not set attribute on $path : $_"
  }
}
'
  if command -v powershell.exe &>/dev/null; then
    powershell.exe -NoProfile -NonInteractive -Command "$ps_script" 2>/dev/null \
      && ok "Set file attributes via PowerShell" \
      || warn "PowerShell attribute setting failed (non-critical)"
  fi

  echo ""
  log "Manual step: in OneDrive Settings → Backup → Manage backup,"
  log "ensure the repository folder is not being backed up, or use"
  log "OneDrive's 'Selective sync' to exclude the build/ folder."
}

cmd_status() {
  log "OneDrive sync status (via PowerShell)…"
  if ! command -v powershell.exe &>/dev/null; then
    err "PowerShell not available."
    exit 1
  fi

  powershell.exe -NoProfile -NonInteractive -Command '
    $onedrive = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
    if ($onedrive) {
      Write-Host "OneDrive is running (PID: $($onedrive.Id))"
      # Check sync state via COM / registry
      $key = "HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Personal"
      if (Test-Path $key) {
        $syncStatus = Get-ItemProperty $key -Name "ScopeIdToSyncStatus" -ErrorAction SilentlyContinue
        if ($syncStatus) {
          Write-Host "Sync status: $($syncStatus.ScopeIdToSyncStatus)"
        }
      }
    } else {
      Write-Host "OneDrive is NOT running."
    }
  ' 2>/dev/null || warn "Could not query OneDrive status"
}

# ── Entry point ───────────────────────────────────────────────────────────────
COMMAND="${1:---check}"
case "$COMMAND" in
  --check)          cmd_check ;;
  --paths)          cmd_paths ;;
  --setup-excludes) cmd_setup_excludes ;;
  --status)         cmd_status ;;
  -h|--help)
    grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
    ;;
  *)
    err "Unknown command: $COMMAND"
    echo "Run with --help for usage." >&2
    exit 1
    ;;
esac
