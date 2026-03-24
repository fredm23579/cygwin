# CLAUDE.md — Cygwin Project Guide for AI Assistants

> **Purpose**: This file provides Claude (and other AI assistants) with the context, conventions,
> architecture, and development guidelines needed to contribute effectively to the Cygwin project.

---

## Project Overview

**Cygwin** is a POSIX-compatible Unix/Linux environment for Microsoft Windows. It provides:

- A large collection of GNU/open-source tools ported to Windows
- A POSIX API compatibility layer (`cygwin1.dll`) enabling Unix software to run on Windows
- A C standard library (`newlib`) with full POSIX compliance
- Board support packages for embedded systems (`libgloss`)
- A complete development ecosystem (compiler, linker, debugger, shell, etc.)

**Official site**: https://cygwin.com
**Bug tracker**: https://cygwin.com/bugzilla/
**Mailing list**: cygwin@cygwin.com
**License**: GPL v3+ (Cygwin DLL), mixed open-source licenses per component

---

## Repository Layout

```
cygwin/
├── CLAUDE.md                    # This file — AI assistant guide
├── README.md                    # Project overview and quick-start
├── README                       # Legacy plain-text README (kept for compatibility)
├── .github/
│   └── workflows/
│       ├── cygwin.yml           # Main CI: Fedora cross-build + Windows native build
│       └── update-deps.yml      # Automated dependency/version check workflow
├── scripts/
│   ├── windows/                 # Modern Windows compatibility scripts (new)
│   │   ├── setup-windows.ps1   # PowerShell: one-shot Windows environment setup
│   │   ├── wintools-detect.sh  # Detect installed Windows tools from Cygwin
│   │   ├── vscode-integration.sh # VSCode workspace and extension setup
│   │   ├── ai-tools-config.sh  # AI tool integration helpers (Claude, Copilot, etc.)
│   │   ├── cloud-storage.sh    # OneDrive / Google Drive mount helpers
│   │   └── self-update.sh      # Self-update: check & pull latest Cygwin packages
│   └── update-check.sh         # Check for stale build dependencies
├── winsup/                      # Windows support layer (Cygwin core)
│   ├── cygwin/                  # Cygwin DLL source (~101 .cc/.c files)
│   ├── cygserver/               # Cygwin server daemon
│   ├── utils/                   # Utility programs (cygpath, mount, ps, etc.)
│   ├── doc/                     # User guide, API guide, FAQ (DocBook XML)
│   └── testsuite/               # Cygwin test suite (DejaGnu)
├── newlib/                      # POSIX C standard library (libc + libm)
├── libgloss/                    # Board support packages & startup code
├── include/                     # Shared C/C++ header files
├── config/                      # Autotools build configuration helpers
├── texinfo/                     # Texinfo documentation toolchain
├── configure                    # Top-level autoconf configure script
├── Makefile.def / Makefile.tpl  # Build definitions and templates
└── .appveyor.yml                # AppVeyor CI (Windows, VS2019)
```

---

## Architecture Deep-Dive

### The Cygwin DLL (`winsup/cygwin/`)

The heart of the project. `cygwin1.dll` implements the POSIX API on top of Win32:

| Module | Purpose |
|---|---|
| `dcrt0.cc` | DLL entry point, C runtime initialization |
| `syscalls.cc` | POSIX syscall implementations (read, write, open, …) |
| `devices.cc` | Virtual device layer (/dev/null, /dev/tty, etc.) |
| `spawn.cc` | Process creation (fork/exec emulation on Windows) |
| `sigproc.cc` | Signal handling and delivery |
| `cygthread.cc` | Thread management (pthreads on Win32) |
| `dtable.cc` | File descriptor table |
| `environ.cc` | Environment variable management |
| `dir.cc` | Directory operations |
| `dlfcn.cc` | Dynamic linking (dlopen/dlsym) |
| `path.cc` | POSIX ↔ Win32 path translation |
| `advapi32.cc` | Windows security / registry autoloads |
| `autoload.cc` | Lazy DLL loading infrastructure |

### Path Translation (`winsup/cygwin/path.cc`)

One of the most critical modules. It converts between:
- POSIX paths: `/usr/bin/gcc`, `/cygdrive/c/Windows`
- Win32 paths: `C:\cygwin64\usr\bin\gcc.exe`, `C:\Windows`

The `cygpath` utility (`winsup/utils/cygpath.cc`) exposes this to shell scripts.

### Utilities (`winsup/utils/`)

End-user command-line tools installed alongside the DLL:

| Tool | Purpose |
|---|---|
| `cygpath` | Convert paths between POSIX/Win32 formats |
| `mount` / `umount` | Manage Cygwin mount points |
| `ps` | List processes (POSIX-style, shows Cygwin processes) |
| `kill` | Send signals to processes |
| `regtool` | Read/write/query Windows registry from command line |
| `mkpasswd` / `mkgroup` | Generate `/etc/passwd` and `/etc/group` from Windows |
| `locale` | Locale configuration |
| `ldd` | List dynamic dependencies |
| `cygcheck` | System diagnostic and package checker |
| `strace` | Trace Cygwin system calls |
| `dumper` | Create minidumps |
| `getfacl` / `setfacl` | POSIX ACL management |

---

## Build System

Cygwin uses the **GNU Autotools** build system (autoconf + automake).

### Prerequisites (Linux/Fedora cross-compile)

```bash
# Fedora / RHEL
dnf install autoconf automake make patch perl \
    mingw64-gcc-c++ mingw64-winpthreads-static mingw64-zlib-static \
    cygwin64-gcc-c++ cygwin64-gettext cygwin64-libbfd cygwin64-libiconv cygwin64-zlib \
    cocom dblatex docbook2X docbook-xsl xmlto \
    python3 python3-lxml python3-ply

# Ubuntu / Debian (cross-compile)
apt-get install autoconf automake make patch perl \
    mingw-w64 python3 python3-lxml python3-ply
```

### Prerequisites (Windows native — Cygwin terminal)

Install Cygwin with these packages:
```
autoconf automake make patch perl cocom gcc-g++
gettext-devel libiconv-devel libzstd-devel zlib-devel
mingw64-x86_64-gcc-g++ mingw64-x86_64-zlib
dejagnu dblatex docbook2X docbook-xml45 docbook-xsl xmlto
python39-lxml python39-ply
texlive-collection-latexrecommended texlive-collection-fontsrecommended
texlive-collection-pictures
```

### Build Steps

```bash
# 1. Generate autotools files (only needed once or after changes to configure.ac)
cd winsup && ./autogen.sh && cd ..

# 2. Configure out-of-tree build
mkdir build install
cd build
../configure --target=x86_64-pc-cygwin --prefix=$(realpath ../install)

# 3. Compile
make -j$(nproc)

# 4. Install locally
make install

# 5. Build and install documentation
make -C x86_64-pc-cygwin/newlib info man
make -C x86_64-pc-cygwin/newlib install-info install-man
```

---

## Development Conventions

### Code Style

- **Language**: C++ (`.cc`) and C (`.c`) — POSIX C++ with Win32 headers
- **Indentation**: 2 spaces (no tabs) in most winsup code
- **Line length**: ~80 characters preferred
- **Comments**: Use `/* */` for block comments, `//` for line comments
- **Naming**:
  - Functions/methods: `lower_case_with_underscores`
  - Classes: `CamelCase`
  - Macros: `ALL_CAPS`
  - Private members: often prefixed with `_` or `cyg_`

### Commit Message Style

Follow the existing convention seen in git history:

```
Component: Brief imperative summary (50 chars max)

Longer explanation if needed. Wrap at 72 characters.
Reference Bugzilla issues as: https://cygwin.com/bugzilla/show_bug.cgi?id=NNNNN
```

Examples from history:
- `Cygwin: pthread: Fix a race issue introduced by the commit 2c5433e5da82`
- `arm: emit .type %function directive in FUNC_START macro`
- `newlib: libm: skip "long double" complex functions if long double != double`

### Testing

```bash
# Run the full Cygwin test suite (requires Windows + Cygwin installed)
cd build
export PATH=x86_64-pc-cygwin/winsup/testsuite/testinst/bin:$PATH
cd x86_64-pc-cygwin/winsup
make check AM_COLOR_TESTS=always
```

Test logs end up in `build/x86_64-pc-cygwin/winsup/testsuite/`.

---

## Windows Compatibility Notes

### Path Handling

Always use `cygpath` to convert paths when bridging Cygwin ↔ Windows:

```bash
# Cygwin → Win32
cygpath -w /usr/bin/gcc        # → C:\cygwin64\usr\bin\gcc.exe
cygpath -w /cygdrive/c/Users   # → C:\Users

# Win32 → Cygwin (use single quotes to avoid backslash interpretation by bash)
cygpath 'C:\Users\fred'        # → /cygdrive/c/Users/fred

# For use in Windows commands (short 8.3 path)
cygpath -ds "C:\Program Files" # → C:/PROGRA~1
```

### Line Endings

Always configure git for correct line ending handling:

```bash
git config core.autocrlf input   # Convert CRLF→LF on checkout (Windows hosts)
```

The repository's `.gitattributes` handles this automatically for most files.

### Launching Windows Applications from Cygwin

```bash
# Open file in default Windows application
cygstart document.pdf

# Launch VSCode from Cygwin terminal
cygstart "$(cygpath -w /usr/local/bin/code)" .

# Open Windows Explorer
explorer.exe "$(cygpath -w /home/user)"
```

### PowerShell Integration

```bash
# Call PowerShell from Cygwin
powershell.exe -Command "Get-Process"

# Run a .ps1 script
powershell.exe -ExecutionPolicy Bypass -File "$(cygpath -w script.ps1)"

# Use PowerShell for Windows-specific tasks
powershell.exe -Command "Get-WmiObject Win32_OperatingSystem | Select Caption,Version"
```

---

## Modern Tool Integrations

### VSCode

The repository includes `.vscode/` configuration (see `scripts/windows/vscode-integration.sh`
for setup). Key extensions recommended for Cygwin development:

- `ms-vscode.cpptools` — C/C++ IntelliSense
- `ms-vscode.cmake-tools` — CMake support (if used)
- `mads-hartmann.bash-ide-vscode` — Bash script support
- `timonwong.shellcheck` — Shell script linting
- `ms-vscode-remote.remote-wsl` — WSL remote development

Launch VSCode from Cygwin:
```bash
# If code is in PATH
code .

# If not (Windows installation)
/cygdrive/c/Users/$USER/AppData/Local/Programs/Microsoft\ VS\ Code/Code.exe .
```

### Git / GitHub

```bash
# Standard workflow
git checkout -b feature/my-fix
git add winsup/cygwin/my-file.cc
git commit -m "Cygwin: fix the thing"
git push -u origin feature/my-fix
```

The CI runs automatically on push. Check `.github/workflows/cygwin.yml` for details.

### AI Tools (Copilot, Claude, ChatGPT, Gemini)

When using AI tools to work on this codebase:
- Point the AI at this `CLAUDE.md` for context
- Provide relevant source files (e.g., `winsup/cygwin/path.cc`) as context
- Be specific about the target: `x86_64-pc-cygwin` (the primary build target)
- Mention that this is C++ with Win32 APIs, not standard Linux C++

GitHub Copilot works well in VSCode with the C/C++ extension enabled.

### Cloud Storage (OneDrive / Google Drive)

If your Cygwin installation lives under a synced folder, be aware:
- **Do not** put build artifacts in synced folders (creates conflicts)
- Use `out-of-tree builds`: configure into a folder **outside** the sync boundary
- See `scripts/windows/cloud-storage.sh` for mount-point helpers

---

## Self-Update and Dependency Management

### Updating Cygwin Packages

```bash
# Check for package updates
scripts/windows/self-update.sh --check

# Apply updates (calls Cygwin setup.exe)
scripts/windows/self-update.sh --update

# Update specific packages
scripts/windows/self-update.sh --packages gcc-g++,make,autoconf
```

### Checking Build Dependencies

```bash
# Check that all required build tools are available
scripts/update-check.sh

# Output shows version of each required tool and whether it meets minimums
```

### Automated Updates (GitHub Actions)

`.github/workflows/update-deps.yml` runs weekly and:
1. Checks Cygwin mirror for updated package versions
2. Checks actions/checkout, actions/upload-artifact for new releases
3. Opens a PR if updates are available

---

## Common Tasks

### Adding a New Utility to `winsup/utils/`

1. Create `winsup/utils/mytool.cc`
2. Add it to `winsup/utils/Makefile.am`:
   ```makefile
   bin_PROGRAMS += mytool
   mytool_SOURCES = mytool.cc
   mytool_LDADD = $(LIBCYGWIN)
   ```
3. Regenerate Makefile: `autoreconf -fi` in `winsup/`
4. Rebuild: `make -C build x86_64-pc-cygwin/winsup/utils/`

### Modifying the Cygwin DLL

1. Edit relevant `.cc` file in `winsup/cygwin/`
2. Rebuild just the DLL: `make -C build x86_64-pc-cygwin/winsup/cygwin/`
3. Test by installing the new DLL and running the test suite
4. **Do not break the ABI** — the DLL must remain binary-compatible

### Working on Documentation

DocBook XML source lives in `winsup/doc/`. Build HTML:
```bash
make -C build x86_64-pc-cygwin/winsup/doc/
# Output in: build/x86_64-pc-cygwin/winsup/doc/cygwin-ug-net/
```

---

## CI/CD Pipeline

### GitHub Actions (`.github/workflows/cygwin.yml`)

| Job | OS | Purpose |
|---|---|---|
| `fedora-build` | Ubuntu + Fedora container | Cross-compile x86_64-pc-cygwin on Linux |
| `windows-build` | Windows Server (latest) | Native build and full test suite |

Triggered on: every push to any branch except `master` (which is an alias for `main`).

Artifacts uploaded: test logs from `windows-build` job.

Documentation deployed to cygwin.com on pushes to `main` and release tags.

### AppVeyor (`.appveyor.yml`)

Supplemental CI on Windows using Visual Studio 2019. Runs on `master` and release tag branches.

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---|---|---|
| `cygwin1.dll not found` | DLL not in PATH | Add Cygwin `bin/` to system PATH |
| Fork failed (EAGAIN) | ASLR conflict | Run `rebaseall` from Cygwin dash shell |
| Mount point issues | Stale `/etc/fstab` | Run `mount -a` or edit `/etc/fstab` |
| Line ending issues | git autocrlf | `git config core.autocrlf input` |
| Build fails: `configure: error` | Missing dep | Check `config.log` for details |
| Windows Defender blocking | False positive | Add Cygwin directory to exclusions |
| Slow file I/O | Real-time protection | See above — add exclusions |

---

## Resources

| Resource | URL |
|---|---|
| Official website | https://cygwin.com |
| Package search | https://cygwin.com/packages/ |
| Mailing list archives | https://cygwin.com/ml/ |
| Bugzilla | https://cygwin.com/bugzilla/ |
| User guide | https://cygwin.com/cygwin-ug-net/ |
| API reference | https://cygwin.com/cygwin-api/ |
| FAQ | https://cygwin.com/faq/ |
| Source browser (upstream) | https://sourceware.org/git/cygwin |
| Windows Subsystem for Linux | https://learn.microsoft.com/en-us/windows/wsl/ |

---

## Key Differences: Cygwin vs WSL

| Feature | Cygwin | WSL 2 |
|---|---|---|
| Architecture | POSIX layer over Win32 | Linux kernel VM |
| Performance | Good; some overhead for fork/exec | Near-native Linux |
| Windows integration | Excellent (native Win32 access) | Good (via `/mnt/c/`) |
| GUI apps | Yes (X11 via Cygwin/X) | Yes (WSLg in Win11) |
| Compatibility | High for Unix tools | Very high (full Linux) |
| Package manager | Cygwin setup.exe | apt, yum, etc. |
| Use case | Windows-native Unix toolchain | Full Linux environment |

Both are valid choices — Cygwin excels when deep Windows API integration is needed.
