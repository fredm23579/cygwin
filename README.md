# Cygwin — POSIX on Windows

[![CI: Fedora cross-build](https://github.com/fredm23579/cygwin/actions/workflows/cygwin.yml/badge.svg)](https://github.com/fredm23579/cygwin/actions/workflows/cygwin.yml)

> **Cygwin** provides a large collection of GNU and open-source tools that deliver a
> POSIX/Linux-like environment on Microsoft Windows, along with a compatibility layer
> (`cygwin1.dll`) that lets software written for Unix run on Windows with little or no
> modification.

---

## Table of Contents

- [What Is Cygwin?](#what-is-cygwin)
- [Quick Install (End Users)](#quick-install-end-users)
- [Quick Start (Developers)](#quick-start-developers)
- [Building from Source](#building-from-source)
- [Modern Windows Tool Integration](#modern-windows-tool-integration)
- [Repository Structure](#repository-structure)
- [CI/CD Pipeline](#cicd-pipeline)
- [Self-Update & Maintenance](#self-update--maintenance)
- [Contributing](#contributing)
- [Resources](#resources)
- [License](#license)

---

## What Is Cygwin?

Cygwin is **not** a way to run Linux software natively on Windows — it is a translation
layer. When a program calls `fork()` or `open("/etc/passwd")`, Cygwin intercepts those calls
and translates them into equivalent Win32 API calls, all transparently.

Key components:

| Component | Description |
|---|---|
| `cygwin1.dll` | The POSIX compatibility DLL — the core of the project |
| `newlib` | Full C standard library (libc + libm) with POSIX extensions |
| `libgloss` | Board support packages and hardware startup code |
| `winsup/utils/` | Unix-like utilities: `cygpath`, `mount`, `ps`, `kill`, `regtool`, … |
| `winsup/doc/` | Comprehensive documentation: user guide, API reference, FAQ |

---

## Quick Install (End Users)

**Download the Cygwin installer for your platform:**

| Platform | Installer |
|---|---|
| 64-bit Windows | [setup-x86_64.exe](https://cygwin.com/setup-x86_64.exe) |

Run the installer and select the packages you need. Cygwin itself includes a package manager
for subsequent installs.

```powershell
# PowerShell: silent install with common development packages
.\setup-x86_64.exe -q -P gcc-g++,make,git,vim,curl,wget,python3
```

See [scripts/windows/setup-windows.ps1](scripts/windows/setup-windows.ps1) for an automated
one-shot Windows developer environment setup.

---

## Quick Start (Developers)

Once Cygwin is installed, open the **Cygwin Terminal** and you get a full Bash shell:

```bash
# Your Windows drives are mounted under /cygdrive/
ls /cygdrive/c/Users/

# Convert between path formats
cygpath -w /usr/bin/gcc        # → C:\cygwin64\usr\bin\gcc.exe
cygpath /cygdrive/c/Users      # → /cygdrive/c/Users (already POSIX)

# Run Windows tools from the Cygwin shell
explorer.exe .
powershell.exe -Command "Get-Process"
notepad.exe "$(cygpath -w /etc/hosts)"

# Launch VSCode
code .
```

### Windows Terminal Integration

Add Cygwin as a profile in **Windows Terminal** (`settings.json`):

```json
{
  "name": "Cygwin",
  "commandline": "C:\\cygwin64\\bin\\bash.exe --login -i",
  "icon": "C:\\cygwin64\\Cygwin.ico",
  "startingDirectory": "%USERPROFILE%"
}
```

---

## Building from Source

### Option A: Cross-compile on Linux (Recommended for Development)

```bash
# 1. Install build dependencies (Fedora/RHEL)
sudo dnf install autoconf automake make patch perl cocom \
    mingw64-gcc-c++ mingw64-winpthreads-static mingw64-zlib-static \
    cygwin64-gcc-c++ cygwin64-gettext cygwin64-libbfd cygwin64-libiconv cygwin64-zlib \
    dblatex docbook2X docbook-xsl xmlto python3 python3-lxml python3-ply

# Ubuntu/Debian equivalent
sudo apt-get install autoconf automake make patch perl mingw-w64 \
    python3 python3-lxml python3-ply

# 2. Generate autotools build files
cd winsup && ./autogen.sh && cd ..

# 3. Configure out-of-tree build
mkdir build install
cd build
../configure --target=x86_64-pc-cygwin --prefix=$(realpath ../install)

# 4. Build (parallel)
make -j$(nproc)

# 5. Install locally
make install

# 6. Build documentation
make -C x86_64-pc-cygwin/newlib info man
make -C x86_64-pc-cygwin/newlib install-info install-man
```

### Option B: Native Build on Windows (Inside Cygwin Terminal)

Install the required Cygwin packages (see [CLAUDE.md](CLAUDE.md) for the full list), then:

```bash
cd winsup && ./autogen.sh && cd ..
mkdir build install
cd build
../configure --prefix=$(realpath ../install) -v
export MAKEFLAGS=-j$(nproc)
make && make install
```

### Option C: Automated Setup via PowerShell

```powershell
# Run from an elevated PowerShell prompt
.\scripts\windows\setup-windows.ps1 -InstallCygwin -BuildFromSource
```

---

## Modern Windows Tool Integration

Cygwin works seamlessly with the modern Windows developer ecosystem.

### VSCode

```bash
# Initialize VSCode workspace with recommended extensions
bash scripts/windows/vscode-integration.sh --init

# Open current directory in VSCode
code .

# Debug a Cygwin program (requires launch.json configuration)
code --goto winsup/cygwin/syscalls.cc:42
```

### PowerShell 7+

```bash
# Detect PowerShell version from Cygwin
bash scripts/windows/wintools-detect.sh --powershell

# Bridge: call PowerShell from a Cygwin script
powershell.exe -ExecutionPolicy Bypass -Command "..."

# Or use the helper function (add to ~/.bashrc):
posh() { powershell.exe -ExecutionPolicy Bypass -Command "$@"; }
```

### Git & GitHub

```bash
# Recommended git config for Cygwin
git config --global core.autocrlf input
git config --global core.fileMode false    # Windows doesn't track file modes

# GitHub CLI (gh) — install via Cygwin or Windows
gh pr create --title "My fix" --body "Fixes issue #123"
```

### AI Tools (Copilot, Claude, ChatGPT, Gemini)

- **GitHub Copilot**: Install the VSCode extension — works with Cygwin C/C++ files
- **Claude**: Use `CLAUDE.md` in the repo root for project context (this repo is pre-configured)
- **ChatGPT / Gemini**: Paste relevant source file snippets for targeted help
- See `scripts/windows/ai-tools-config.sh` for shell-level AI integration helpers

### Cloud Storage (OneDrive, Google Drive)

```bash
# Check if repo is in a synced folder (can cause issues)
bash scripts/windows/cloud-storage.sh --check

# Recommended: keep build artifacts OUTSIDE synced folders
bash scripts/windows/cloud-storage.sh --setup-excludes
```

### Windows Subsystem for Linux (WSL)

Cygwin and WSL can coexist. From WSL you can access Cygwin executables:

```bash
# From WSL — call a Cygwin utility
/mnt/c/cygwin64/bin/cygpath.exe -w /usr/bin/gcc
```

---

## Repository Structure

```
cygwin/
├── CLAUDE.md                   # AI assistant context guide
├── README.md                   # This file
├── .github/workflows/          # GitHub Actions CI/CD
├── scripts/windows/            # Modern Windows integration scripts
│   ├── setup-windows.ps1      # Automated Windows dev environment setup
│   ├── self-update.sh         # Check & apply Cygwin package updates
│   ├── wintools-detect.sh     # Detect Windows tools from Cygwin shell
│   ├── vscode-integration.sh  # VSCode workspace configuration
│   ├── ai-tools-config.sh     # AI assistant integration helpers
│   └── cloud-storage.sh       # OneDrive/Google Drive helpers
├── scripts/update-check.sh    # Verify build dependency versions
├── winsup/                    # Windows support layer (Cygwin DLL + utils)
├── newlib/                    # C standard library
├── libgloss/                  # Board support packages
├── include/                   # Shared headers
└── config/ texinfo/           # Build system support files
```

---

## CI/CD Pipeline

| Workflow | Trigger | Description |
|---|---|---|
| Fedora cross-build | Every push | Cross-compiles x86_64-pc-cygwin on Linux |
| Windows native build | Every push | Builds and runs full test suite on Windows |
| Update deps check | Weekly (Monday) | Checks for updated tools and action versions |

**Status**: Check the badge at the top of this file, or see the
[Actions tab](https://github.com/fredm23579/cygwin/actions).

Test logs from the Windows build job are uploaded as artifacts and kept for 30 days.

---

## Self-Update & Maintenance

### Update Cygwin Packages

```bash
# Check which installed packages have updates available
bash scripts/windows/self-update.sh --check

# Apply all available updates (launches Cygwin setup.exe)
bash scripts/windows/self-update.sh --update

# Update only build-critical packages
bash scripts/windows/self-update.sh --packages gcc-g++,make,autoconf,automake
```

### Check Build Dependencies

```bash
# Verify all build tools meet minimum version requirements
bash scripts/update-check.sh
```

### Keep Actions Up To Date

The `update-deps.yml` workflow runs every Monday and checks for new versions of:
- `actions/checkout`
- `actions/upload-artifact`
- `cygwin/cygwin-install-action`

---

## Contributing

1. **Fork** this repository on GitHub
2. **Create a branch**: `git checkout -b fix/my-improvement`
3. **Make changes** following the conventions in [CLAUDE.md](CLAUDE.md)
4. **Test** your changes (run the test suite if possible)
5. **Commit** with a clear message: `Component: describe the fix`
6. **Push** and open a **Pull Request**

For bugs in the **upstream Cygwin project**, please report to
[cygwin.com/bugzilla](https://cygwin.com/bugzilla/) or post to the
[Cygwin mailing list](mailto:cygwin@cygwin.com).

### Code Style Quick Reference

- C++ (`.cc`) with 2-space indentation
- Function names: `lower_case_with_underscores`
- Class names: `CamelCase`
- Macros: `ALL_CAPS`
- Commit style: `Component: brief imperative description`

---

## Resources

| Resource | Link |
|---|---|
| Official website | https://cygwin.com |
| Package search | https://cygwin.com/packages/ |
| User guide | https://cygwin.com/cygwin-ug-net/ |
| API reference | https://cygwin.com/cygwin-api/ |
| FAQ | https://cygwin.com/faq/ |
| Bug tracker | https://cygwin.com/bugzilla/ |
| Mailing list | https://cygwin.com/ml/ |
| Windows Terminal | https://aka.ms/terminal |
| VSCode | https://code.visualstudio.com |
| WSL documentation | https://learn.microsoft.com/windows/wsl/ |

---

## License

Cygwin is released under the **GNU General Public License v3** (or later) for the DLL itself.
Individual components carry their own compatible open-source licenses:

- `newlib/` — BSD-like licenses (see `COPYING.NEWLIB`)
- `libgloss/` — Mixed (see `COPYING.LIBGLOSS`)
- Utilities — GPL v2 or later

See `COPYING`, `COPYING3`, `COPYING.LIB`, `COPYING3.LIB`, `COPYING.NEWLIB`,
and `COPYING.LIBGLOSS` in the root of this repository for full license texts.
