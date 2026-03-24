#!/usr/bin/env bash
# =============================================================================
# update-check.sh — Verify Cygwin build dependency versions
# =============================================================================
#
# Checks that all tools required to build Cygwin from source are present and
# meet the minimum version requirements. Prints a clear pass/fail summary.
#
# Usage:
#   bash scripts/update-check.sh [OPTIONS]
#
# Options:
#   --strict    Exit with non-zero code if any check fails (useful in CI)
#   --json      Output results as JSON
#   --quiet     Only show failures
#   -h, --help  Show this help
#
# Exit codes:
#   0  All required tools found and version constraints satisfied
#   1  One or more required tools missing or outdated
#
# =============================================================================
set -euo pipefail

# ── Colour helpers ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

ok()  { printf "  ${GREEN}PASS${RESET}  %-28s %s\n" "$1" "$2"; }
fail(){ printf "  ${RED}FAIL${RESET}  %-28s %s\n" "$1" "$2"; }
warn(){ printf "  ${YELLOW}WARN${RESET}  %-28s %s\n" "$1" "$2"; }
skip(){ printf "  ${CYAN}SKIP${RESET}  %-28s %s\n" "$1" "$2"; }

# ── Options ───────────────────────────────────────────────────────────────────
STRICT=false; OUTPUT_JSON=false; QUIET=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=true ;;
    --json)   OUTPUT_JSON=true ;;
    --quiet)  QUIET=true ;;
    -h|--help)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# ── Version comparison helper ─────────────────────────────────────────────────
# version_gte INSTALLED MINIMUM → returns 0 if installed >= minimum
version_gte() {
  local installed="$1" minimum="$2"
  # Use sort -V (version sort) to compare; if installed sorts last it's >= min
  printf '%s\n%s\n' "$minimum" "$installed" \
    | sort -V --check=quiet 2>/dev/null || return 1
}

# ── Check runner ──────────────────────────────────────────────────────────────
PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0
declare -A RESULTS

check_tool() {
  local name="$1"      # human-readable name
  local cmd="$2"       # command to run for version output
  local min_ver="$3"   # minimum acceptable version (empty = any)
  local required="$4"  # "required" or "optional"
  local ver_regex="${5:-[0-9][0-9.]*}"  # regex to extract version string

  local version found=false
  if version=$(eval "$cmd" 2>&1 | grep -oP "$ver_regex" | head -1); then
    found=true
  fi

  if ! $found || [[ -z "$version" ]]; then
    RESULTS["$name"]="missing"
    if [[ "$required" == "required" ]]; then
      $QUIET || fail "$name" "NOT FOUND (required)"
      (( FAIL_COUNT++ )) || true
    else
      $QUIET || warn "$name" "not found (optional)"
      (( WARN_COUNT++ )) || true
    fi
    return
  fi

  if [[ -n "$min_ver" ]] && ! version_gte "$version" "$min_ver"; then
    RESULTS["$name"]="outdated:${version}"
    if [[ "$required" == "required" ]]; then
      $QUIET || fail "$name" "v${version} found, need >= ${min_ver}"
      (( FAIL_COUNT++ )) || true
    else
      $QUIET || warn "$name" "v${version} found, recommend >= ${min_ver}"
      (( WARN_COUNT++ )) || true
    fi
  else
    RESULTS["$name"]="ok:${version}"
    $QUIET || ok "$name" "v${version}${min_ver:+ (>= ${min_ver})}"
    (( PASS_COUNT++ )) || true
  fi
}

# ── Checks ────────────────────────────────────────────────────────────────────

$QUIET || printf "\n${BOLD}Build dependency check${RESET}\n\n"
$QUIET || printf "%-6s %-28s %s\n" "Status" "Tool" "Version"
$QUIET || printf '%s\n' "$(printf '─%.0s' {1..60})"

# Core build tools
check_tool "gcc"       "gcc --version"     "10.0"  "required"
check_tool "g++"       "g++ --version"     "10.0"  "required"
check_tool "make"      "make --version"    "4.0"   "required"
check_tool "autoconf"  "autoconf --version" "2.69" "required"
check_tool "automake"  "automake --version" "1.15" "required"
check_tool "perl"      "perl --version"    "5.26"  "required"
check_tool "patch"     "patch --version"   "2.7"   "required"

# Documentation tools
check_tool "python3"   "python3 --version" "3.6"   "required"
check_tool "xmlto"     "xmlto --version"   ""      "optional"
check_tool "dblatex"   "dblatex --version" ""      "optional"
check_tool "docbook2X" "db2x_docbook2man --version" "" "optional" '[0-9]\S*'

# Cross-compile / MinGW tools
check_tool "x86_64-w64-mingw32-gcc" \
  "x86_64-w64-mingw32-gcc --version" "10.0" "optional"

# Python modules required by the build
check_tool "python3-lxml" \
  "python3 -c 'import lxml; print(lxml.__version__)'" "4.0" "required"
check_tool "python3-ply" \
  "python3 -c 'import ply; print(ply.__version__)'" "3.9" "required"

# Git (always needed for development)
check_tool "git"       "git --version"    "2.30"  "required"

# Cygwin-specific tools (only relevant inside Cygwin)
if [[ "$(uname -o 2>/dev/null)" == "Cygwin" ]]; then
  $QUIET || echo ""
  $QUIET || printf "${BOLD}Cygwin-specific tools:${RESET}\n"

  check_tool "cygpath"   "cygpath --version" "" "required"
  check_tool "cocom"     "cocom --version"   "" "optional"
  check_tool "dejagnu"   "runtest --version" "" "optional"
fi

# ── Python module detail check ────────────────────────────────────────────────
$QUIET || echo ""
$QUIET || printf "${BOLD}Python module details:${RESET}\n"
python3 -c "
import sys
modules = {'lxml': '4.0', 'ply': '3.9'}
for mod, min_ver in modules.items():
    try:
        m = __import__(mod)
        ver = getattr(m, '__version__', 'unknown')
        print(f'  {mod}: {ver}')
    except ImportError:
        print(f'  {mod}: NOT INSTALLED')
" 2>/dev/null || true

# ── Summary ───────────────────────────────────────────────────────────────────
$QUIET || echo ""
printf "${BOLD}Summary:${RESET} "
printf "${GREEN}%d passed${RESET}, " "$PASS_COUNT"
printf "${YELLOW}%d warnings${RESET}, " "$WARN_COUNT"
printf "${RED}%d failed${RESET}\n" "$FAIL_COUNT"

if (( FAIL_COUNT > 0 )); then
  echo ""
  echo "To install missing tools on Fedora/RHEL:"
  echo "  sudo dnf install autoconf automake make patch perl gcc-c++ python3 python3-lxml python3-ply"
  echo ""
  echo "To install inside Cygwin:"
  echo "  Run Cygwin setup.exe and add: autoconf automake make patch perl gcc-g++ python3-lxml python3-ply"
fi

if $OUTPUT_JSON; then
  echo '{'
  local_sep=''
  for tool in "${!RESULTS[@]}"; do
    val="${RESULTS[$tool]}"
    status="${val%%:*}"
    version="${val#*:}"
    [[ "$status" == "missing" ]] && version=''
    printf '%s  "%s": {"status": "%s", "version": "%s"}\n' \
      "$local_sep" "$tool" "$status" "$version"
    local_sep=','
  done
  echo '}'
fi

# Strict mode: exit non-zero if any required tool is missing or outdated
$STRICT && (( FAIL_COUNT > 0 )) && exit 1 || exit 0
