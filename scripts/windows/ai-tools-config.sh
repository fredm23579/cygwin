#!/usr/bin/env bash
# =============================================================================
# ai-tools-config.sh — AI assistant integration helpers for Cygwin development
# =============================================================================
#
# Provides shell-level helpers for working with AI coding assistants
# (Claude, GitHub Copilot CLI, ChatGPT, Google Gemini, Meta AI, etc.)
# from within the Cygwin environment.
#
# Usage — source this file to get helper functions in your shell:
#   source scripts/windows/ai-tools-config.sh
#
# Or run directly for one-shot operations:
#   bash scripts/windows/ai-tools-config.sh [COMMAND]
#
# Commands (when run directly):
#   --setup         Print recommended ~/.bashrc additions
#   --check         Check which AI tools are available
#   --context       Print a project context summary (useful for pasting into AI)
#   --copilot       Launch GitHub Copilot CLI (gh copilot suggest / explain)
#   -h, --help      Show this help
#
# When SOURCED, the following functions become available:
#   ai_context      Print project context for pasting into any AI chat
#   ai_explain FILE [LINE_RANGE]   Ask Copilot CLI to explain code
#   ai_suggest PROMPT              Ask Copilot CLI for a shell command
#   ai_review FILE                 Summarise a file for AI review
#   claude_context                 Print CLAUDE.md location for Claude
#
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ── Colour helpers ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
  BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; CYAN=''; YELLOW=''; BOLD=''; RESET=''
fi

ok()  { printf "${GREEN}[✓]${RESET} %s\n" "$*"; }
log() { printf "${CYAN}[ai-tools]${RESET} %s\n" "$*"; }
warn(){ printf "${YELLOW}[!]${RESET} %s\n" "$*"; }

# ── Tool detection ─────────────────────────────────────────────────────────────
_has() { command -v "$1" &>/dev/null; }

detect_ai_tools() {
  echo ""
  printf "${BOLD}AI tools available in this environment:${RESET}\n\n"

  # GitHub Copilot CLI (installed as gh extension)
  if _has gh && gh copilot --version &>/dev/null 2>&1; then
    ok "GitHub Copilot CLI  (gh copilot suggest / gh copilot explain)"
  else
    warn "GitHub Copilot CLI  — install: gh extension install github/gh-copilot"
  fi

  # Claude Desktop (Anthropic) — Windows app, not in Cygwin PATH normally
  local claude_exe
  claude_exe=$(cygpath "${LOCALAPPDATA:-C:\\Users\\Default\\AppData\\Local}/AnthropicClaude/claude.exe" 2>/dev/null || true)
  if [[ -x "$claude_exe" ]]; then
    ok "Claude Desktop      (Anthropic — $claude_exe)"
  else
    warn "Claude Desktop      — download: https://claude.ai/download"
  fi

  # Claude CLI / API (if claude command available or ANTHROPIC_API_KEY set)
  if _has claude || [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    ok "Claude CLI/API      (ANTHROPIC_API_KEY is set or 'claude' is in PATH)"
  else
    warn "Claude API          — set ANTHROPIC_API_KEY for API access"
  fi

  # OpenAI / ChatGPT CLI
  if _has openai || [[ -n "${OPENAI_API_KEY:-}" ]]; then
    ok "OpenAI/ChatGPT      (OPENAI_API_KEY is set)"
  else
    warn "OpenAI CLI          — set OPENAI_API_KEY or install openai-python CLI"
  fi

  # Google Gemini (via gcloud or API)
  if _has gcloud || [[ -n "${GOOGLE_API_KEY:-}" ]]; then
    ok "Google Gemini       (gcloud or GOOGLE_API_KEY is set)"
  else
    warn "Google Gemini       — install gcloud CLI or set GOOGLE_API_KEY"
  fi

  echo ""
  log "Context guide: ${REPO_ROOT}/CLAUDE.md"
  log "Run 'ai_context' (after sourcing this file) to get a paste-ready project summary."
}

# ── Project context printer ────────────────────────────────────────────────────
# Outputs a compact project summary suitable for pasting into any AI chat window
# to give the assistant context about the Cygwin codebase.
ai_context() {
  local claude_md="${REPO_ROOT}/CLAUDE.md"
  cat <<CONTEXT
=== Cygwin project context ===
Project: Cygwin — POSIX/Unix compatibility layer for Windows
Language: C++ (.cc) and C (.c) with Win32 APIs
Build: GNU Autotools (configure/make), target x86_64-pc-cygwin
Key dirs:
  winsup/cygwin/   — Cygwin DLL source (POSIX API → Win32 translation)
  winsup/utils/    — User utilities (cygpath, mount, ps, regtool, …)
  newlib/          — C standard library (libc + libm)
  libgloss/        — Board support packages
Style: 2-space indent, snake_case functions, CamelCase classes
Test: DejaGnu suite (make check in winsup/)

Full guide: ${claude_md}
CONTEXT
}

# ── Claude-specific helper ────────────────────────────────────────────────────
claude_context() {
  local claude_md="${REPO_ROOT}/CLAUDE.md"
  if [[ -f "$claude_md" ]]; then
    log "CLAUDE.md is at: ${claude_md}"
    log "Pass this file as context when starting a Claude session."
    echo ""
    echo "Quick copy (Windows path for drag-and-drop):"
    cygpath -w "$claude_md"
  else
    warn "CLAUDE.md not found. Run the setup scripts first."
  fi
}

# ── GitHub Copilot CLI wrappers ────────────────────────────────────────────────

# ai_explain FILE [START_LINE[-END_LINE]]
# Asks Copilot to explain code in a file (or a specific line range).
ai_explain() {
  local file="${1:-}"
  local range="${2:-}"
  [[ -z "$file" ]] && { echo "Usage: ai_explain <file> [start[-end]]" >&2; return 1; }
  [[ ! -f "$file" ]] && { echo "File not found: $file" >&2; return 1; }

  if ! _has gh || ! gh copilot --version &>/dev/null 2>&1; then
    warn "GitHub Copilot CLI not available."
    warn "Install with: gh extension install github/gh-copilot"
    return 1
  fi

  local content
  if [[ -n "$range" ]]; then
    local start end
    IFS='-' read -r start end <<< "$range"
    end="${end:-$start}"
    content=$(sed -n "${start},${end}p" "$file")
  else
    content=$(cat "$file")
  fi

  echo "$content" | gh copilot explain -
}

# ai_suggest PROMPT
# Asks Copilot to suggest a shell command for the given natural-language prompt.
ai_suggest() {
  local prompt="$*"
  [[ -z "$prompt" ]] && { echo "Usage: ai_suggest <prompt>" >&2; return 1; }

  if ! _has gh || ! gh copilot --version &>/dev/null 2>&1; then
    warn "GitHub Copilot CLI not available."
    return 1
  fi

  gh copilot suggest "$prompt"
}

# ai_review FILE
# Prints the file contents with line numbers in a format ready to paste into
# any AI chat for a code review session.
ai_review() {
  local file="${1:-}"
  [[ -z "$file" ]] && { echo "Usage: ai_review <file>" >&2; return 1; }
  [[ ! -f "$file" ]] && { echo "File not found: $file" >&2; return 1; }

  echo "=== Code review request for: ${file} ==="
  echo "Project: Cygwin (POSIX compatibility layer for Windows)"
  echo "Language: $(file "$file" | grep -oP '(?<=: )[^,]+' || echo 'C/C++')"
  echo ""
  cat -n "$file"
  echo ""
  echo "=== End of file ==="
  echo "Please review the above code for correctness, style, potential bugs,"
  echo "and Windows/POSIX compatibility issues."
}

# ── Recommended ~/.bashrc additions ───────────────────────────────────────────
print_bashrc_additions() {
  cat <<'BASHRC'
# ── Cygwin AI Tools ────────────────────────────────────────────────────────────
# Source the AI helpers from the Cygwin repo (adjust path as needed)
CYGWIN_REPO="${HOME}/cygwin"
if [[ -f "${CYGWIN_REPO}/scripts/windows/ai-tools-config.sh" ]]; then
  source "${CYGWIN_REPO}/scripts/windows/ai-tools-config.sh"
fi

# API keys (set these if you use the respective services)
# export ANTHROPIC_API_KEY='your-key-here'    # Claude API
# export OPENAI_API_KEY='your-key-here'        # OpenAI / ChatGPT
# export GOOGLE_API_KEY='your-key-here'        # Google Gemini

# Quick aliases
alias ai='ai_suggest'          # ai "how do I list open TCP sockets"
alias explain='ai_explain'     # explain winsup/cygwin/path.cc 1-50
alias review='ai_review'       # review winsup/cygwin/spawn.cc
BASHRC
}

# ── Entry point (when run directly, not sourced) ───────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  COMMAND="${1:---check}"
  case "$COMMAND" in
    --check)    detect_ai_tools ;;
    --context)  ai_context ;;
    --setup)    print_bashrc_additions ;;
    --copilot)  shift; ai_suggest "$@" ;;
    -h|--help)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
      ;;
    *)
      echo "Unknown command: $COMMAND" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
fi
