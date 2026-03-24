#!/usr/bin/env bash
# =============================================================================
# wintools-detect.sh — Detect installed Windows tools from within Cygwin
# =============================================================================
#
# Scans for commonly used Windows developer tools and reports their presence,
# version, and Cygwin-accessible path. Useful for:
#   - Verifying a new developer workstation is properly set up
#   - Debugging PATH or integration issues
#   - Scripts that conditionally use Windows-native tools
#
# Usage:
#   bash scripts/windows/wintools-detect.sh [OPTIONS]
#
# Options:
#   --all          Check every tool (default)
#   --powershell   Check PowerShell only
#   --vscode       Check VSCode only
#   --git          Check Git installations only
#   --ai           Check AI tools (Claude, Copilot, etc.)
#   --cloud        Check cloud storage tools
#   --microsoft    Check Microsoft ecosystem tools
#   --json         Output results as JSON
#   --quiet        Only print failures / missing tools
#   -h, --help     Show this help
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

# ── Option parsing ────────────────────────────────────────────────────────────
CHECK_ALL=true
CHECK_POWERSHELL=false; CHECK_VSCODE=false; CHECK_GIT=false
CHECK_AI=false; CHECK_CLOUD=false; CHECK_MICROSOFT=false
OUTPUT_JSON=false; QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)         CHECK_ALL=true ;;
    --powershell)  CHECK_POWERSHELL=true; CHECK_ALL=false ;;
    --vscode)      CHECK_VSCODE=true;     CHECK_ALL=false ;;
    --git)         CHECK_GIT=true;        CHECK_ALL=false ;;
    --ai)          CHECK_AI=true;         CHECK_ALL=false ;;
    --cloud)       CHECK_CLOUD=true;      CHECK_ALL=false ;;
    --microsoft)   CHECK_MICROSOFT=true;  CHECK_ALL=false ;;
    --json)        OUTPUT_JSON=true ;;
    --quiet)       QUIET=true ;;
    -h|--help)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

if $CHECK_ALL; then
  CHECK_POWERSHELL=true; CHECK_VSCODE=true; CHECK_GIT=true
  CHECK_AI=true; CHECK_CLOUD=true; CHECK_MICROSOFT=true
fi

# ── Result tracking ───────────────────────────────────────────────────────────
declare -A RESULTS   # tool_name → "found|version|path" or "missing"
FOUND_COUNT=0; MISSING_COUNT=0

# ── Core detection function ───────────────────────────────────────────────────
# detect_tool NAME [SEARCH_PATHS...] [-- VERSION_CMD]
# Sets RESULTS[NAME] and prints a status line.
detect_tool() {
  local name="$1"; shift
  local version_cmd=(); local search_paths=()

  # Split arguments at '--' to separate paths from version command
  local in_version_cmd=false
  for arg in "$@"; do
    if [[ "$arg" == '--' ]]; then in_version_cmd=true; continue; fi
    if $in_version_cmd; then
      version_cmd+=("$arg")
    else
      search_paths+=("$arg")
    fi
  done

  # Try each candidate path in order.
  # Use eval + printf to expand globs safely while still supporting patterns
  # like "/cygdrive/c/Users/*/AppData/..." without word-splitting on spaces
  # that may be present in Windows paths.
  local found_path=''
  for candidate in "${search_paths[@]}"; do
    # Use nullglob so unmatched globs produce nothing rather than a literal string
    local expanded_paths
    expanded_paths=$(
      bash -c 'set -f; shopt -s nullglob; for p in '"$(printf '%q' "$candidate")"'; do [[ -x "$p" ]] && printf "%s\n" "$p" && break; done'
    )
    if [[ -n "$expanded_paths" ]]; then
      found_path=$(head -1 <<< "$expanded_paths")
      break
    fi
  done

  # Also try PATH lookup if no explicit paths given
  if [[ -z "$found_path" ]]; then
    if command -v "$name" &>/dev/null; then
      found_path=$(command -v "$name")
    fi
  fi

  if [[ -n "$found_path" ]]; then
    local version='unknown'
    if [[ ${#version_cmd[@]} -gt 0 ]]; then
      version=$("$found_path" "${version_cmd[@]}" 2>&1 | head -1 | sed 's/\r//' || true)
    fi
    RESULTS["$name"]="found|${version}|${found_path}"
    (( FOUND_COUNT++ )) || true
    $QUIET || printf "  ${GREEN}✓${RESET} %-30s %s\n" "$name" "$version"
  else
    RESULTS["$name"]='missing'
    (( MISSING_COUNT++ )) || true
    printf "  ${YELLOW}✗${RESET} %-30s not found\n" "$name"
  fi
}

# ── Section printer ───────────────────────────────────────────────────────────
section() { $QUIET || printf "\n${BOLD}${CYAN}▶ %s${RESET}\n" "$1"; }

# ── Windows-specific path helpers ─────────────────────────────────────────────
# Expand a Windows environment variable like %PROGRAMFILES% into a Cygwin path.
# Captures the whole value as one string before passing to cygpath, so that
# paths containing spaces (e.g. "C:\Program Files") are handled correctly.
win_env() {
  local var="$1"
  local win_path
  win_path=$(cmd.exe /c "echo %${var}%" 2>/dev/null | tr -d '\r\n')
  # Guard against unexpanded variables (cmd echoes the literal %VAR% when unset)
  [[ -z "$win_path" || "$win_path" == "%${var}%" ]] && return 0
  cygpath "$win_path" 2>/dev/null || true
}

PROGRAMFILES=$(win_env PROGRAMFILES)
PROGRAMFILES_X86=$(win_env "PROGRAMFILES(X86)")
LOCALAPPDATA=$(win_env LOCALAPPDATA)
APPDATA=$(win_env APPDATA)
USERPROFILE=$(win_env USERPROFILE)

# ── PowerShell ────────────────────────────────────────────────────────────────
if $CHECK_POWERSHELL; then
  section "PowerShell"
  # PowerShell 7+ (pwsh) is the modern cross-platform version
  detect_tool 'pwsh (PowerShell 7+)' \
    "${PROGRAMFILES}/PowerShell/7/pwsh.exe" \
    "${PROGRAMFILES_X86}/PowerShell/7/pwsh.exe" \
    -- --version

  # Windows PowerShell 5.1 (built-in, ships with every modern Windows install)
  detect_tool 'powershell (Windows PS 5.1)' \
    '/cygdrive/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' \
    -- -Command '$PSVersionTable.PSVersion.ToString()'
fi

# ── VSCode ────────────────────────────────────────────────────────────────────
if $CHECK_VSCODE; then
  section "Visual Studio Code"
  detect_tool 'code (VSCode stable)' \
    "${LOCALAPPDATA}/Programs/Microsoft VS Code/Code.exe" \
    "${PROGRAMFILES}/Microsoft VS Code/Code.exe" \
    -- --version

  detect_tool 'code-insiders (VSCode Insiders)' \
    "${LOCALAPPDATA}/Programs/Microsoft VS Code Insiders/Code - Insiders.exe" \
    -- --version
fi

# ── Git installations ─────────────────────────────────────────────────────────
if $CHECK_GIT; then
  section "Git"
  # Cygwin git (in Cygwin PATH — usually /usr/bin/git)
  detect_tool 'git (Cygwin)' /usr/bin/git -- --version

  # Git for Windows (Git Bash / MinGW)
  detect_tool 'git (Git for Windows)' \
    "${PROGRAMFILES}/Git/bin/git.exe" \
    "${PROGRAMFILES_X86}/Git/bin/git.exe" \
    -- --version

  # GitHub CLI
  detect_tool 'gh (GitHub CLI)' \
    "${PROGRAMFILES}/GitHub CLI/gh.exe" \
    "${LOCALAPPDATA}/Programs/GitHub CLI/gh.exe" \
    -- --version

  # Git Credential Manager (included with Git for Windows)
  detect_tool 'git-credential-manager' \
    "${PROGRAMFILES}/Git/mingw64/bin/git-credential-manager.exe" \
    "${LOCALAPPDATA}/Programs/Git Credential Manager/git-credential-manager.exe" \
    -- --version

  # Windows built-in SSH
  detect_tool 'ssh (Windows OpenSSH)' \
    '/cygdrive/c/Windows/System32/OpenSSH/ssh.exe' \
    -- -V
fi

# ── AI tools ─────────────────────────────────────────────────────────────────
if $CHECK_AI; then
  section "AI Developer Tools"

  # Claude Desktop (Anthropic)
  detect_tool 'Claude Desktop' \
    "${LOCALAPPDATA}/AnthropicClaude/claude.exe" \
    "${LOCALAPPDATA}/Programs/claude/claude.exe"

  # GitHub Copilot CLI (gh extension: gh copilot)
  detect_tool 'gh copilot (GitHub Copilot CLI)' \
    "${LOCALAPPDATA}/Programs/GitHub CLI/gh.exe" \
    "${PROGRAMFILES}/GitHub CLI/gh.exe"

  # Node.js (required by many AI tool CLIs)
  detect_tool 'node (Node.js)' \
    "${PROGRAMFILES}/nodejs/node.exe" \
    "${LOCALAPPDATA}/Programs/nodejs/node.exe" \
    -- --version

  # npm
  detect_tool 'npm' \
    "${PROGRAMFILES}/nodejs/npm.cmd" \
    "${LOCALAPPDATA}/Programs/nodejs/npm.cmd"

  # Python 3 (used by AI toolchains, Cygwin build deps, etc.)
  detect_tool 'python3' /usr/bin/python3 -- --version
fi

# ── Cloud storage ─────────────────────────────────────────────────────────────
if $CHECK_CLOUD; then
  section "Cloud Storage"

  # Microsoft OneDrive
  detect_tool 'OneDrive' \
    "${LOCALAPPDATA}/Microsoft/OneDrive/OneDrive.exe" \
    "${APPDATA}/Microsoft/Windows/Start Menu/Programs/OneDrive.lnk"

  # Google Drive desktop client (google drive for desktop)
  detect_tool 'Google Drive (DriveFS)' \
    "${PROGRAMFILES}/Google/Drive File Stream/GoogleDriveFS.exe" \
    "${PROGRAMFILES_X86}/Google/Drive File Stream/GoogleDriveFS.exe"

  # Dropbox
  detect_tool 'Dropbox' \
    "${LOCALAPPDATA}/Dropbox/Dropbox.exe" \
    "${APPDATA}/Dropbox/client/Dropbox.exe"
fi

# ── Microsoft ecosystem ───────────────────────────────────────────────────────
if $CHECK_MICROSOFT; then
  section "Microsoft Ecosystem"

  # Windows Terminal (the modern replacement for conhost/cmd)
  detect_tool 'Windows Terminal' \
    "${LOCALAPPDATA}/Microsoft/WindowsApps/wt.exe"

  # WSL 2
  detect_tool 'wsl (Windows Subsystem for Linux)' \
    '/cygdrive/c/Windows/System32/wsl.exe' \
    -- --version

  # Visual Studio (Build Tools or IDE)
  detect_tool 'MSBuild (Visual Studio)' \
    "${PROGRAMFILES_X86}/Microsoft Visual Studio/2022/BuildTools/MSBuild/Current/Bin/MSBuild.exe" \
    "${PROGRAMFILES_X86}/Microsoft Visual Studio/2022/Community/MSBuild/Current/Bin/MSBuild.exe" \
    "${PROGRAMFILES_X86}/Microsoft Visual Studio/2022/Professional/MSBuild/Current/Bin/MSBuild.exe" \
    "${PROGRAMFILES_X86}/Microsoft Visual Studio/2022/Enterprise/MSBuild/Current/Bin/MSBuild.exe" \
    -- -version

  # .NET / dotnet CLI
  detect_tool 'dotnet (.NET SDK)' \
    "${PROGRAMFILES}/dotnet/dotnet.exe" \
    -- --version

  # WinGet (Windows Package Manager)
  detect_tool 'winget' \
    "${LOCALAPPDATA}/Microsoft/WindowsApps/winget.exe" \
    -- --version

  # Chocolatey
  detect_tool 'choco (Chocolatey)' \
    '/cygdrive/c/ProgramData/chocolatey/bin/choco.exe' \
    -- --version

  # Scoop (user-space package manager)
  detect_tool 'scoop' \
    "${USERPROFILE}/scoop/shims/scoop.cmd"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
if $OUTPUT_JSON; then
  # Emit JSON for use by other scripts
  echo '{'
  local_sep=''
  for tool in "${!RESULTS[@]}"; do
    val="${RESULTS[$tool]}"
    if [[ "$val" == 'missing' ]]; then
      printf '%s  "%s": {"found": false}\n' "$local_sep" "$tool"
    else
      IFS='|' read -r _ version path <<< "$val"
      version="${version//\"/\\\"}"
      path="${path//\\/\\\\}"
      printf '%s  "%s": {"found": true, "version": "%s", "path": "%s"}\n' \
        "$local_sep" "$tool" "$version" "$path"
    fi
    local_sep=','
  done
  echo '}'
else
  $QUIET || echo ''
  printf "${BOLD}Summary:${RESET} ${GREEN}%d found${RESET}, ${YELLOW}%d missing${RESET}\n" \
    "$FOUND_COUNT" "$MISSING_COUNT"
fi
