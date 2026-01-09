# env-installer

Cross-platform environment setup installer.

Goals:

- Run on:
  - Lubuntu / Ubuntu / Debian
  - Arch-based systems
  - Proxmox (Debian-based)
  - macOS
- Provide an idempotent, scriptable way to configure a system.
- Support:
  - Full install: all steps
  - Partial install: run selected steps only

Current status (v0):

- `install.sh`:
  - Detects platform, distro, package manager.
  - Lists and runs step scripts in `steps/`.
- `lib/common.sh`:
  - Logging helpers (`log`, `warn`, `die`).
  - Detection helpers (`detect_platform`, `detect_arch`, `detect_distro`, `detect_pkg_manager`).
  - Basic command helpers (`available`, `first_of`, `run`).
  - Root helpers (`init_sudo`, `as_root`).
  - Minimal `ensure_packages` abstraction (APT / pacman / Homebrew).
- `steps/10-env-info.sh`:
  - Prints out detected environment info.
  - Non-destructive: safe to run on any machine.

Nothing in this version makes persistent changes to the system.
Future versions will add concrete, idempotent setup steps.
