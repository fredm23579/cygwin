#!/usr/bin/env bash
# =============================================================================
# vscode-integration.sh — Configure VSCode for Cygwin development
# =============================================================================
#
# Sets up a VSCode workspace optimised for working on the Cygwin codebase.
# Creates .vscode/ configuration files with:
#   - Recommended C/C++ extensions
#   - IntelliSense configuration pointing at Cygwin headers
#   - Shell integration (Cygwin Bash as the default terminal)
#   - Useful editor defaults (trimming whitespace, 80-char ruler, etc.)
#   - Launch configuration for debugging Cygwin utilities
#
# Usage:
#   bash scripts/windows/vscode-integration.sh [OPTIONS]
#
# Options:
#   --init      Create .vscode/ workspace files (default)
#   --install   Install recommended VSCode extensions
#   --open      Open the workspace in VSCode after setup
#   --purge     Remove the .vscode/ directory
#   -h, --help  Show this help
#
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VSCODE_DIR="${REPO_ROOT}/.vscode"

# ── Colour helpers ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; CYAN=''; BOLD=''; RESET=''
fi
ok()  { printf "${GREEN}[✓]${RESET} %s\n" "$*"; }
log() { printf "${CYAN}[vscode]${RESET} %s\n" "$*"; }

# ── Locate VSCode executable ──────────────────────────────────────────────────
find_vscode() {
  # Prefer the code shim in PATH (works for both system and user installs)
  if command -v code &>/dev/null; then
    echo 'code'; return
  fi

  local localappdata
  localappdata=$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r\n')
  local programfiles
  programfiles=$(cmd.exe /c 'echo %PROGRAMFILES%' 2>/dev/null | tr -d '\r\n')

  local candidates=(
    "$(cygpath "${localappdata}")/Programs/Microsoft VS Code/bin/code"
    "$(cygpath "${programfiles}")/Microsoft VS Code/bin/code"
  )
  for c in "${candidates[@]}"; do
    [[ -x "$c" ]] && echo "$c" && return
  done
  echo ''
}

CODE_BIN=$(find_vscode)

# ── Option parsing ────────────────────────────────────────────────────────────
COMMAND='init'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --init)    COMMAND='init' ;;
    --install) COMMAND='install' ;;
    --open)    COMMAND='open' ;;
    --purge)   COMMAND='purge' ;;
    -h|--help)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# ── Workspace configuration files ─────────────────────────────────────────────
create_extensions_json() {
  cat > "${VSCODE_DIR}/extensions.json" <<'EXTEOF'
{
  // Workspace-recommended extensions for Cygwin C/C++ development.
  // VSCode will prompt to install these when you open this folder.
  "recommendations": [
    // C/C++ language support and IntelliSense
    "ms-vscode.cpptools",
    "ms-vscode.cpptools-extension-pack",
    // CMake support (if used)
    "ms-vscode.cmake-tools",
    // Bash/shell script editing and linting
    "mads-hartmann.bash-ide-vscode",
    "timonwong.shellcheck",
    // XML editing (DocBook source files in winsup/doc/)
    "redhat.vscode-xml",
    // EditorConfig support (respects per-directory code style)
    "editorconfig.editorconfig",
    // Git integration
    "eamodio.gitlens",
    // Spell-checker for comments and docs
    "streetsidesoftware.code-spell-checker",
    // GitHub Copilot (AI pair programmer)
    "github.copilot",
    "github.copilot-chat",
    // Makefile syntax highlighting
    "ms-vscode.makefile-tools",
    // Remote development (WSL, containers, SSH)
    "ms-vscode-remote.vscode-remote-extensionpack"
  ],
  "unwantedRecommendations": []
}
EXTEOF
  ok "Created .vscode/extensions.json"
}

create_settings_json() {
  # Use forward-slash (mixed) paths for JSON: cygpath -m gives C:/cygwin64 style.
  # Forward slashes are valid in Windows paths and need no escaping in JSON,
  # unlike backslashes which would need to be doubled (\\).
  local cygwin_root
  cygwin_root=$(cygpath -m '/')   # e.g. C:/cygwin64

  cat > "${VSCODE_DIR}/settings.json" <<SETTINGSEOF
{
  // ── Editor defaults ────────────────────────────────────────────────────────
  "editor.rulers": [80, 120],
  "editor.trimAutoWhitespace": true,
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "editor.tabSize": 2,
  "editor.detectIndentation": true,
  "editor.formatOnSave": false,

  // ── Line ending: always use LF (Unix-style) ────────────────────────────────
  "files.eol": "\n",

  // ── C/C++ IntelliSense (ms-vscode.cpptools) ────────────────────────────────
  "C_Cpp.default.compilerPath": "${cygwin_root}/bin/gcc.exe",
  "C_Cpp.default.includePath": [
    "\${workspaceFolder}/**",
    "${cygwin_root}/usr/include",
    "${cygwin_root}/usr/include/w32api"
  ],
  "C_Cpp.default.defines": [
    "__CYGWIN__",
    "_WIN32",
    "__x86_64__"
  ],
  "C_Cpp.default.cppStandard": "c++17",
  "C_Cpp.default.cStandard": "c11",
  "C_Cpp.default.intelliSenseMode": "windows-gcc-x64",

  // ── Integrated terminal: use Cygwin Bash ───────────────────────────────────
  "terminal.integrated.defaultProfile.windows": "Cygwin Bash",
  "terminal.integrated.profiles.windows": {
    "Cygwin Bash": {
      "path": "${cygwin_root}/bin/bash.exe",
      "args": ["--login", "-i"],
      "icon": "terminal-bash",
      "env": {
        "CHERE_INVOKING": "1",
        "CYGWIN": "winsymlinks:nativestrict"
      }
    },
    "PowerShell": {
      "source": "PowerShell",
      "icon": "terminal-powershell"
    },
    "Command Prompt": {
      "path": "cmd.exe",
      "args": [],
      "icon": "terminal-cmd"
    }
  },

  // ── File associations ──────────────────────────────────────────────────────
  "files.associations": {
    "*.cc": "cpp",
    "*.h": "c",
    "*.in": "makefile",
    "*.ac": "shellscript",
    "*.am": "makefile",
    "configure": "shellscript",
    "*.xml": "xml"
  },

  // ── Exclude build/generated directories from search ────────────────────────
  "files.exclude": {
    "build/": true,
    "install/": true,
    "**/.deps": true,
    "**/.libs": true,
    "**/*.o": true,
    "**/*.lo": true,
    "**/*.la": true,
    "**/autom4te.cache": true
  },
  "search.exclude": {
    "build/": true,
    "install/": true,
    "newlib/": false,
    "libgloss/": false
  },

  // ── Git ────────────────────────────────────────────────────────────────────
  "git.autofetch": true,
  "git.confirmSync": false,

  // ── ShellCheck (timonwong.shellcheck) ─────────────────────────────────────
  "shellcheck.enable": true,
  "shellcheck.executablePath": "/usr/bin/shellcheck",

  // ── Makefile tools ─────────────────────────────────────────────────────────
  "makefile.makePath": "/usr/bin/make",
  "makefile.buildLog": "build/build.log"
}
SETTINGSEOF
  ok "Created .vscode/settings.json"
}

create_launch_json() {
  cat > "${VSCODE_DIR}/launch.json" <<'LAUNCHEOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      // Debug a Cygwin utility (e.g. cygpath, mount, ps)
      // Adjust 'program' and 'args' per the tool under investigation.
      "name": "Debug Cygwin utility",
      "type": "cppdbg",
      "request": "launch",
      "program": "${workspaceFolder}/build/x86_64-pc-cygwin/winsup/utils/${input:utilityName}",
      "args": [],
      "stopAtEntry": false,
      "cwd": "${workspaceFolder}",
      "environment": [],
      "externalConsole": false,
      "MIMode": "gdb",
      "miDebuggerPath": "/usr/bin/gdb",
      "setupCommands": [
        {
          "description": "Enable pretty-printing for gdb",
          "text": "-enable-pretty-printing",
          "ignoreFailures": true
        }
      ]
    },
    {
      // Attach to a running Cygwin process by PID
      "name": "Attach to Cygwin process",
      "type": "cppdbg",
      "request": "attach",
      "program": "${input:executablePath}",
      "processId": "${command:pickProcess}",
      "MIMode": "gdb",
      "miDebuggerPath": "/usr/bin/gdb"
    }
  ],
  "inputs": [
    {
      "id": "utilityName",
      "type": "promptString",
      "description": "Name of the utility executable to debug",
      "default": "cygpath"
    },
    {
      "id": "executablePath",
      "type": "promptString",
      "description": "Full path to the executable",
      "default": ""
    }
  ]
}
LAUNCHEOF
  ok "Created .vscode/launch.json"
}

create_tasks_json() {
  cat > "${VSCODE_DIR}/tasks.json" <<'TASKSEOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Build Cygwin",
      "type": "shell",
      "command": "make -j$(nproc) -C build",
      "group": { "kind": "build", "isDefault": true },
      "presentation": { "reveal": "always", "panel": "shared" },
      "problemMatcher": "$gcc"
    },
    {
      "label": "Configure build (first time)",
      "type": "shell",
      "command": "bash -lc 'mkdir -p build install && (cd winsup && ./autogen.sh) && (cd build && ../configure --target=x86_64-pc-cygwin --prefix=$(realpath ../install))'",
      "group": "build",
      "presentation": { "reveal": "always", "panel": "shared" },
      "problemMatcher": []
    },
    {
      "label": "Clean build",
      "type": "shell",
      "command": "make -C build clean",
      "group": "build",
      "presentation": { "reveal": "always", "panel": "shared" },
      "problemMatcher": []
    },
    {
      "label": "Run Cygwin tests",
      "type": "shell",
      "command": "bash -lc 'cd build/x86_64-pc-cygwin/winsup && make check AM_COLOR_TESTS=always'",
      "group": { "kind": "test", "isDefault": true },
      "presentation": { "reveal": "always", "panel": "shared" },
      "problemMatcher": []
    },
    {
      "label": "Check Windows tools",
      "type": "shell",
      "command": "bash scripts/windows/wintools-detect.sh",
      "group": "none",
      "presentation": { "reveal": "always", "panel": "shared" },
      "problemMatcher": []
    },
    {
      "label": "Check for Cygwin updates",
      "type": "shell",
      "command": "bash scripts/windows/self-update.sh --check",
      "group": "none",
      "presentation": { "reveal": "always", "panel": "shared" },
      "problemMatcher": []
    }
  ]
}
TASKSEOF
  ok "Created .vscode/tasks.json"
}

# ── Command implementations ───────────────────────────────────────────────────
cmd_init() {
  log "Initialising VSCode workspace in ${REPO_ROOT}…"
  mkdir -p "$VSCODE_DIR"
  create_extensions_json
  create_settings_json
  create_launch_json
  create_tasks_json
  ok "VSCode workspace configured. Open this folder in VSCode to get started."
  echo ""
  echo "  Tip: run with --install to also install all recommended extensions."
  echo "  Tip: run with --open to launch VSCode now."
}

cmd_install() {
  if [[ -z "$CODE_BIN" ]]; then
    echo "VSCode (code) not found in PATH or common install locations." >&2
    echo "Install VSCode from https://code.visualstudio.com and rerun." >&2
    exit 1
  fi

  log "Installing recommended extensions…"
  # Parse extension IDs directly from extensions.json to keep a single source
  # of truth. Strips comments (// ...) and extracts quoted publisher.name values.
  local ext_list=()
  if [[ -f "${VSCODE_DIR}/extensions.json" ]]; then
    while IFS= read -r line; do
      # Skip comment lines; extract the quoted extension identifier
      [[ "$line" =~ ^[[:space:]]*/[/*] ]] && continue
      local ext; ext=$(printf '%s' "$line" | grep -oE '"[a-z0-9-]+\.[a-z0-9._-]+"' \
        | tr -d '"' || true)
      [[ -n "$ext" ]] && ext_list+=("$ext")
    done < "${VSCODE_DIR}/extensions.json"
  fi

  # Fallback: hard-coded list keeps installs working even if extensions.json
  # was not yet generated or is unreadable.
  if [[ ${#ext_list[@]} -eq 0 ]]; then
  local ext_list=(
    ms-vscode.cpptools
    ms-vscode.cpptools-extension-pack
    ms-vscode.cmake-tools
    mads-hartmann.bash-ide-vscode
    timonwong.shellcheck
    redhat.vscode-xml
    editorconfig.editorconfig
    eamodio.gitlens
    streetsidesoftware.code-spell-checker
    github.copilot
    github.copilot-chat
    ms-vscode.makefile-tools
    ms-vscode-remote.vscode-remote-extensionpack
  )
  fi

  for ext in "${ext_list[@]}"; do
    log "Installing ${ext}…"
    "$CODE_BIN" --install-extension "$ext" --force 2>/dev/null && ok "$ext" || true
  done

  ok "Extension installation complete."
}

cmd_open() {
  if [[ -z "$CODE_BIN" ]]; then
    echo "VSCode (code) not found. Install from https://code.visualstudio.com" >&2
    exit 1
  fi
  log "Opening ${REPO_ROOT} in VSCode…"
  "$CODE_BIN" "$REPO_ROOT"
}

cmd_purge() {
  if [[ -d "$VSCODE_DIR" ]]; then
    rm -rf "$VSCODE_DIR"
    ok "Removed ${VSCODE_DIR}"
  else
    echo ".vscode/ does not exist — nothing to do."
  fi
}

# ── Entry point ───────────────────────────────────────────────────────────────
case "$COMMAND" in
  init)    cmd_init ;;
  install) [[ ! -d "$VSCODE_DIR" ]] && cmd_init; cmd_install ;;
  open)    [[ ! -d "$VSCODE_DIR" ]] && cmd_init; cmd_open ;;
  purge)   cmd_purge ;;
esac
