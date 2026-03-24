#!/usr/bin/env bash
# =============================================================================
# self-update.sh — Check for and apply Cygwin package updates
# =============================================================================
#
# Wraps the Cygwin setup.exe installer to provide a developer-friendly
# command-line interface for keeping the Cygwin installation current.
#
# Usage:
#   bash scripts/windows/self-update.sh [COMMAND] [OPTIONS]
#
# Commands:
#   --check                 List packages with available updates (default)
#   --update                Apply all available updates (launches setup.exe)
#   --packages PKG[,PKG]    Update only specific packages
#   --info PKG              Show installed vs. available version for a package
#   --find-setup            Locate the Cygwin setup.exe installer
#   --set-mirror URL        Set preferred Cygwin mirror (persisted to config)
#   -h, --help              Show this help
#
# Environment variables (override defaults):
#   CYGWIN_ROOT     Cygwin installation root  (default: C:\cygwin64)
#   CYGWIN_MIRROR   Package mirror URL
#   CYGWIN_SETUP    Path to setup.exe
#   CYGWIN_CACHE    Package download cache directory
#
# =============================================================================
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

log()  { printf "${CYAN}[self-update]${RESET} %s\n" "$*"; }
ok()   { printf "${GREEN}[✓]${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${RESET} %s\n" "$*"; }
err()  { printf "${RED}[✗]${RESET} %s\n" "$*" >&2; }

# ── Configuration ─────────────────────────────────────────────────────────────
CONFIG_FILE="${HOME}/.cygwin-update.conf"

# Load persisted configuration if it exists
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Defaults (can be overridden by env vars or config file)
CYGWIN_ROOT="${CYGWIN_ROOT:-$(cygpath 'C:\cygwin64')}"
CYGWIN_MIRROR="${CYGWIN_MIRROR:-https://mirrors.kernel.org/sourceware/cygwin/}"
CYGWIN_CACHE="${CYGWIN_CACHE:-$(cygpath 'C:\cygwin-cache')}"

# Locate setup.exe: prefer cached copy, then common install locations
find_setup_exe() {
  local candidates=(
    "$(cygpath 'C:\cygwin-cache\setup-x86_64.exe')"
    "$(cygpath 'C:\cache\setup-x86_64.exe')"
    "${CYGWIN_ROOT}/../setup-x86_64.exe"
    "${HOME}/Downloads/setup-x86_64.exe"
    "$(cygpath 'C:\Users\Public\Downloads\setup-x86_64.exe')"
  )
  for p in "${candidates[@]}"; do
    [[ -x "$p" ]] && echo "$p" && return 0
  done

  # Last resort: search common download folders
  find "$(cygpath 'C:\Users')" -name 'setup-x86_64.exe' -maxdepth 4 2>/dev/null \
    | head -1

  return 1
}

CYGWIN_SETUP="${CYGWIN_SETUP:-$(find_setup_exe 2>/dev/null || true)}"

# ── Cygwin package database helpers ───────────────────────────────────────────

# installed_version PKG → prints installed version or "not installed"
installed_version() {
  local pkg="$1"
  local db="${CYGWIN_ROOT}/var/log/setup.log.full"
  if [[ -f "$db" ]]; then
    grep -oP "(?<=inst: )${pkg}-[0-9][^\s]+" "$db" 2>/dev/null | tail -1 \
      | sed "s/^${pkg}-//" || true
  fi
}

# available_version PKG MIRROR → queries the mirror's setup.ini for latest version
available_version() {
  local pkg="$1"
  local mirror="${2:-$CYGWIN_MIRROR}"
  # Download setup.ini if we don't have a cached copy
  local ini_cache="${CYGWIN_CACHE}/setup.ini"
  if [[ ! -f "$ini_cache" ]] || [[ $(( $(date +%s) - $(stat -c %Y "$ini_cache" 2>/dev/null || echo 0) )) -gt 3600 ]]; then
    log "Fetching package index from ${mirror}…"
    mkdir -p "$CYGWIN_CACHE"
    curl -sSf "${mirror}x86_64/setup.ini" -o "$ini_cache" 2>/dev/null || {
      warn "Could not fetch setup.ini from mirror; try --set-mirror <URL>"
      return 1
    }
  fi
  # Parse the version from setup.ini (field after "version:")
  awk -v pkg="$pkg" '
    /^@ / { in_pkg = ($2 == pkg) }
    in_pkg && /^version:/ { print $2; exit }
  ' "$ini_cache" 2>/dev/null || true
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_find_setup() {
  if [[ -n "$CYGWIN_SETUP" ]]; then
    ok "setup.exe found: $CYGWIN_SETUP"
  else
    err "setup.exe not found. Download from https://cygwin.com/install.html"
    err "Set CYGWIN_SETUP=/path/to/setup-x86_64.exe or place it in C:\\cygwin-cache\\"
    exit 1
  fi
}

cmd_set_mirror() {
  local url="$1"
  [[ -z "$url" ]] && { err "Usage: --set-mirror <URL>"; exit 1; }
  echo "CYGWIN_MIRROR='${url}'" > "$CONFIG_FILE"
  ok "Mirror set to: ${url} (saved to ${CONFIG_FILE})"
}

cmd_info() {
  local pkg="$1"
  [[ -z "$pkg" ]] && { err "Usage: --info <package>"; exit 1; }
  local inst avail
  inst=$(installed_version "$pkg")
  avail=$(available_version "$pkg")
  printf "  Package : %s\n" "$pkg"
  printf "  Installed: %s\n" "${inst:-not installed}"
  printf "  Available: %s\n" "${avail:-unknown}"
  [[ "$inst" == "$avail" ]] && ok "Up to date." || warn "Update available!"
}

cmd_check() {
  log "Checking for Cygwin package updates…"
  log "Mirror: ${CYGWIN_MIRROR}"

  # Read installed packages from the Cygwin setup log
  local setup_log="${CYGWIN_ROOT}/var/log/setup.log.full"
  if [[ ! -f "$setup_log" ]]; then
    warn "Cannot read ${setup_log} — check CYGWIN_ROOT (currently: ${CYGWIN_ROOT})"
    warn "Set CYGWIN_ROOT to your Cygwin installation root, e.g.:"
    warn "  export CYGWIN_ROOT=$(cygpath 'C:\\cygwin64')"
    exit 1
  fi

  # Extract unique package names from the install log
  local pkgs
  pkgs=$(grep -oP '(?<=inst: )\S+' "$setup_log" 2>/dev/null \
         | sed 's/-[0-9].*//' | sort -u || true)

  if [[ -z "$pkgs" ]]; then
    warn "Could not determine installed packages from ${setup_log}."
    exit 1
  fi

  local updates=0 total=0
  echo ""
  printf "${BOLD}%-35s %-20s %-20s${RESET}\n" "Package" "Installed" "Available"
  printf '%s\n' "$(printf '─%.0s' {1..77})"

  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    local inst avail
    inst=$(installed_version "$pkg")
    avail=$(available_version "$pkg" 2>/dev/null || echo 'unknown')
    (( total++ )) || true

    if [[ "$inst" != "$avail" && -n "$avail" && "$avail" != 'unknown' ]]; then
      printf "${YELLOW}%-35s %-20s %-20s${RESET}\n" "$pkg" "${inst:-—}" "$avail"
      (( updates++ )) || true
    fi
  done <<< "$pkgs"

  echo ""
  if (( updates > 0 )); then
    warn "${updates} package(s) have updates available."
    log "Run with --update to apply them."
  else
    ok "All ${total} checked packages are up to date."
  fi
}

cmd_update() {
  cmd_find_setup
  log "Launching Cygwin setup.exe for full update…"
  log "Root:   ${CYGWIN_ROOT}"
  log "Mirror: ${CYGWIN_MIRROR}"
  log "Cache:  ${CYGWIN_CACHE}"

  # -q  = quiet mode (no GUI dialogs for package selection)
  # -n  = don't create shortcuts
  # -N  = no start menu
  # -d  = download from internet
  # -O  = only upgrade already-installed packages
  # -R  = installation root
  # -s  = mirror site
  # -l  = local package cache
  local win_root; win_root=$(cygpath -w "$CYGWIN_ROOT")
  local win_cache; win_cache=$(cygpath -w "$CYGWIN_CACHE")

  # Run setup.exe; it will exit when complete (may require elevation)
  cmd.exe /c "$(cygpath -w "$CYGWIN_SETUP")" \
    -q -n -N -d -O \
    -R "$win_root" \
    -s "$CYGWIN_MIRROR" \
    -l "$win_cache" \
    && ok "Update complete." \
    || { err "setup.exe exited with error. Check the setup log."; exit 1; }
}

cmd_update_packages() {
  local packages="$1"
  cmd_find_setup
  log "Updating packages: ${packages}"
  local win_root; win_root=$(cygpath -w "$CYGWIN_ROOT")
  local win_cache; win_cache=$(cygpath -w "$CYGWIN_CACHE")

  cmd.exe /c "$(cygpath -w "$CYGWIN_SETUP")" \
    -q -n -N -d -O \
    -R "$win_root" \
    -s "$CYGWIN_MIRROR" \
    -l "$win_cache" \
    -P "$packages" \
    && ok "Package update complete." \
    || { err "setup.exe exited with error."; exit 1; }
}

# ── Entry point ───────────────────────────────────────────────────────────────
COMMAND='check'
PACKAGES=''
SET_MIRROR_URL=''
INFO_PKG=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)          COMMAND='check' ;;
    --update)         COMMAND='update' ;;
    --find-setup)     COMMAND='find-setup' ;;
    --packages)       COMMAND='update-packages'; PACKAGES="$2"; shift ;;
    --info)           COMMAND='info'; INFO_PKG="$2"; shift ;;
    --set-mirror)     COMMAND='set-mirror'; SET_MIRROR_URL="$2"; shift ;;
    -h|--help)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
      exit 0
      ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

case "$COMMAND" in
  check)           cmd_check ;;
  update)          cmd_update ;;
  update-packages) cmd_update_packages "$PACKAGES" ;;
  info)            cmd_info "$INFO_PKG" ;;
  find-setup)      cmd_find_setup ;;
  set-mirror)      cmd_set_mirror "$SET_MIRROR_URL" ;;
esac
