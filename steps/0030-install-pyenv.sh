#!/usr/bin/env sh
# Step: install-pyenv
#
# Installs pyenv (Python version manager).
#
# Supported:
#   - macOS
#   - Linux: arch, ubuntu
#
# Skipped:
#   - proxmox

set -eu

# --------------------------------------------------------------------
# 1) Load shared helpers
# --------------------------------------------------------------------
# Steps may live under nested scoped directories, so walk upwards until lib/common.sh exists.

SCRIPT_DIR="$(
  CDPATH= cd -- "$(dirname -- "$0")" && pwd
)"

ROOT_DIR="$SCRIPT_DIR"
while [ ! -f "$ROOT_DIR/lib/common.sh" ]; do
  ROOT_DIR="$(
    CDPATH= cd -- "$ROOT_DIR/.." && pwd
  )"

  if [ "$ROOT_DIR" = "/" ]; then
    echo "[ERR] Could not locate repo root (lib/common.sh not found)." >&2
    exit 1
  fi
done

# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"

# --------------------------------------------------------------------
# 2) Logging preamble for this step
# --------------------------------------------------------------------

require_logfile

STEP_TITLE="${STEP_NAME:-install-pyenv}"

add_title "$STEP_TITLE"
add_comments <<EOF
This step installs pyenv.

Behaviour:
  - If pyenv is already installed (either on PATH or at ~/.pyenv/bin/pyenv), no action is taken.
  - On macOS, installs via Homebrew (brew install pyenv).
  - On Arch, installs via pacman (pyenv) and required build deps.
  - On Ubuntu, installs build deps via apt and then installs pyenv via the official installer.
  - Proxmox is explicitly skipped (to avoid unintended installs on hypervisors).

Shell setup:
  This step does NOT modify your shell rc files.
  After install, add the recommended init lines (logged in validation details)
  to your shell config (~/.zshrc, ~/.bashrc, etc) if pyenv is not already on PATH.

EOF

log "$STEP_TITLE: starting (PLATFORM=$PLATFORM, DISTRO=$DISTRO, ARCH=$ARCH, DEVICE_ID=${DEVICE_ID:-unknown}, PKG_MGR=${PKG_MGR:-none})"

# --------------------------------------------------------------------
# Optional DEBUG diagnostics
# --------------------------------------------------------------------
# These diagnostics are emitted only when DEBUG=1.
# They must not affect control flow or stdout parsing.

if [ "${DEBUG:-0}" = "1" ]; then
  log_block <<EOF
DEBUG: step context
  STEP_NAME = ${STEP_NAME:-<unset>}
  SCRIPT    = $(basename "$0")
  LOCATION  = "$SCRIPT_DIR"
EOF
fi

# --------------------------------------------------------------------
# Validation details (reusable block)
# --------------------------------------------------------------------

PYENV_HOME="${PYENV_ROOT:-$HOME/.pyenv}"
PYENV_BIN="$PYENV_HOME/bin/pyenv"

log_validation_details() {
  {
    printf 'Validation details:\n'
    printf '  pyenv (PATH)  : %s\n' "$(command -v pyenv 2>/dev/null || echo "<not found>")"
    printf '  pyenv (local) : %s\n' "$( [ -x "$PYENV_BIN" ] && echo "$PYENV_BIN" || echo "<not found>" )"
    printf '  pyenv version : %s\n' "$(
      if command -v pyenv >/dev/null 2>&1; then
        pyenv --version 2>/dev/null || echo "<version check failed>"
      elif [ -x "$PYENV_BIN" ]; then
        "$PYENV_BIN" --version 2>/dev/null || echo "<version check failed>"
      else
        echo "<not available>"
      fi
    )"
    printf '\nRecommended shell init (zsh/bash):\n'
    printf '  export PYENV_ROOT="%s"\n' "$PYENV_HOME"
    printf '  export PATH="$PYENV_ROOT/bin:$PATH"\n'
    printf '  eval "$(pyenv init -)"\n'
  } | add_comments
}

pyenv_present() {
  command -v pyenv >/dev/null 2>&1 || [ -x "$PYENV_BIN" ]
}

# --------------------------------------------------------------------
# 3) Guards / requirements (PLATFORM / DISTRO / ARCH / DEVICE_ID / PKG_MGR)
# --------------------------------------------------------------------

# Never run on Proxmox (even though it's Debian-based)
if [ "${DISTRO:-}" = "proxmox" ]; then
  log "Skipping: pyenv install is disabled on Proxmox."
  exit 0
fi

case "${PLATFORM:-}" in
  macos)
    # Requires Homebrew
    if [ "${PKG_MGR:-none}" != "brew" ]; then
      log "Skipping: pyenv on macOS requires Homebrew (PKG_MGR=brew)."
      exit 0
    fi
    ;;
  linux)
    # Only support Arch + Ubuntu for this step (matches your usual base targets)
    case "${DISTRO:-}" in
      arch|omarchy|ubuntu|debian)
        : ;;
      *)
        log "Skipping: unsupported Linux distro for pyenv step (DISTRO='${DISTRO:-<unset>}')."
        exit 0
        ;;
    esac
    ;;
  *)
    log "Skipping: unsupported PLATFORM='${PLATFORM:-<unset>}' for pyenv."
    exit 0
    ;;
esac

# If there is no supported package manager, we can't install deps.
if [ "${PKG_MGR:-none}" = "none" ]; then
  die "Cannot install pyenv automatically: no supported package manager detected (PKG_MGR=none)."
fi

# --------------------------------------------------------------------
# 4) Idempotency check (desired state)
# --------------------------------------------------------------------

if pyenv_present; then
  log "pyenv already present; skipping."
  log_validation_details
  exit 0
fi

# --------------------------------------------------------------------
# 5) Apply changes (install / configure)
# --------------------------------------------------------------------

if [ "${PLATFORM:-}" = "macos" ]; then
  log "Installing pyenv via Homebrew (ensure_packages pyenv)..."
  ensure_packages pyenv
else
  # Linux
  case "${DISTRO:-}" in
    arch|omarchy)
      # Arch has pyenv in repos; install build deps commonly needed for building Python.
      log "Installing pyenv via pacman (ensure_packages pyenv + build deps)..."
      ensure_packages pyenv base-devel git curl openssl zlib xz tk readline sqlite libffi
      ;;
    ubuntu|debian)
      # Ubuntu/Debian: install build deps via apt, then install pyenv via official installer.
      log "Installing pyenv build dependencies via apt..."
      ensure_packages \
        make build-essential \
        libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
        curl git \
        libncursesw5-dev xz-utils tk-dev \
        libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

      if ! available curl; then
        die "curl is required to install pyenv on Ubuntu/Debian but was not found after installing deps."
      fi

      log_block <<EOF
Installing pyenv via official installer:
  curl -fsSL https://pyenv.run | bash

Target:
  PYENV_ROOT = $PYENV_HOME
EOF

      # Official installer installs into ~/.pyenv by default
      run sh -c 'curl -fsSL https://pyenv.run | bash'
      ;;
    *)
      die "Unsupported DISTRO='${DISTRO:-}' for pyenv step."
      ;;
  esac
fi

# --------------------------------------------------------------------
# 6) Validate final state (+ validation details)
# --------------------------------------------------------------------

if pyenv_present; then
  log "pyenv installation complete."
  log_validation_details
else
  die "pyenv install was attempted but pyenv is still not available (PATH or $PYENV_BIN)."
fi
