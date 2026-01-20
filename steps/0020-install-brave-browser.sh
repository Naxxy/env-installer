#!/usr/bin/env sh
# Step: install-brave-browser
#
# This step is intended to be run *only* via install.sh, which is responsible for:
#   - Detecting PLATFORM, DISTRO, ARCH, DEVICE_ID, PKG_MGR.
#   - Parsing CLI flags (e.g. --debug).
#   - Initialising a per-run LOGFILE and passing it to this step.
#
# Assumptions (passed from install.sh):
#   - PLATFORM, DISTRO, ARCH, DEVICE_ID, PKG_MGR, LOGFILE, STEP_NAME are exported.
#   - DEBUG is exported and set to "1" or "0".
#   - LOGFILE already exists and is writable.
#
# Responsibilities:
#   - Log a clear step header + description into LOGFILE.
#   - Ensure Brave Browser is installed.
#   - Be idempotent (no changes if already in desired state).
#
# Supported:
#   - macos (brew cask)
#   - linux: arch, ubuntu
#
# Explicitly NOT supported:
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

STEP_TITLE="${STEP_NAME:-install-brave-browser}"

add_title "$STEP_TITLE"
add_comments <<EOF
This step installs Brave Browser.

Behaviour:
  - If Brave is already installed, no action is taken (idempotent).
  - On macOS, installs via Homebrew cask (brave-browser).
  - On Arch/Ubuntu, installs via Brave's official Linux installer script.
  - Proxmox is explicitly skipped.

Environment snapshot:
  PLATFORM   = ${PLATFORM:-<unset>}
  DISTRO     = ${DISTRO:-<unset>}
  ARCH       = ${ARCH:-<unset>}
  DEVICE_ID  = ${DEVICE_ID:-<unset>}
  PKG_MGR    = ${PKG_MGR:-<unset>}
  DEBUG      = ${DEBUG:-0}
  LOGFILE    = ${LOGFILE:-<unset>}
EOF

log "$STEP_TITLE: starting (PLATFORM=$PLATFORM, DISTRO=$DISTRO, ARCH=$ARCH, DEVICE_ID=${DEVICE_ID:-unknown}, PKG_MGR=${PKG_MGR:-none})"

# --------------------------------------------------------------------
# Optional DEBUG diagnostics
# --------------------------------------------------------------------

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

PRIMARY_CMD="brave-browser"

log_validation_details() {
  {
    printf 'Validation details:\n'
    printf '  brave-browser path: %s\n' "$(command -v brave-browser 2>/dev/null || echo "<not found>")"
    printf '  brave-browser version/info: %s\n' "$(brave-browser --version 2>/dev/null || echo "<version check failed>")"
    printf '  macOS app bundle: %s\n' "$( [ -d "/Applications/Brave Browser.app" ] && echo "/Applications/Brave Browser.app" || echo "<not found>" )"
  } | add_comments
}

# --------------------------------------------------------------------
# 3) Guards / requirements (PLATFORM / DISTRO / ARCH / DEVICE_ID / PKG_MGR)
# --------------------------------------------------------------------

# Never run on Proxmox (even though it's Debian-based)
if [ "${DISTRO:-}" = "proxmox" ]; then
  log "Skipping: Brave install is disabled on Proxmox."
  exit 0
fi

case "${PLATFORM:-}" in
  macos)
    # macOS must have Homebrew available (your install-homebrew step should run earlier)
    if [ "${PKG_MGR:-none}" != "brew" ]; then
      log "Skipping: Brave on macOS requires Homebrew (PKG_MGR=brew)."
      exit 0
    fi
    ;;
  linux)
    # Only Arch/Ubuntu (as requested)
    case "${DISTRO:-}" in
      arch|ubuntu)
        : ;;
      *)
        log "Skipping: Brave step supports only Arch/Ubuntu on Linux (got DISTRO='${DISTRO:-<unset>}')."
        exit 0
        ;;
    esac
    ;;
  *)
    log "Skipping: unsupported PLATFORM='${PLATFORM:-<unset>}' for Brave."
    exit 0
    ;;
esac

# --------------------------------------------------------------------
# 4) Idempotency check (desired state)
# --------------------------------------------------------------------

# Linux: brave-browser binary exists
if available brave-browser; then
  log "Brave Browser already present; skipping."
  log_validation_details
  exit 0
fi

# macOS: Brave app bundle exists (Homebrew cask installs the .app)
if [ "${PLATFORM:-}" = "macos" ] && [ -d "/Applications/Brave Browser.app" ]; then
  log "Brave Browser.app already present; skipping."
  log_validation_details
  exit 0
fi

# --------------------------------------------------------------------
# 5) Apply changes (install / configure)
# --------------------------------------------------------------------

if [ "${PLATFORM:-}" = "macos" ]; then
  log "Installing Brave Browser via Homebrew cask..."
  run brew install --cask brave-browser
else
  # Linux (Arch/Ubuntu)
  # Use Brave's official Linux installer script (handles repo setup + install).
  # Ensure curl exists (script fetch).
  log "Installing Brave Browser via Brave's official Linux installer script..."

  if ! available curl; then
    log "curl not found; installing via ensure_packages..."
    if ! ensure_packages curl; then
      die "Failed to install curl; cannot continue Brave install."
    fi
  fi

  log_block <<EOF
Linux installer:
  curl -fsS https://dl.brave.com/install.sh | sh
EOF

  # shellcheck disable=SC2002
  run sh -c 'curl -fsS https://dl.brave.com/install.sh | sh'
fi

# --------------------------------------------------------------------
# 6) Validate final state (+ validation details)
# --------------------------------------------------------------------

if [ "${PLATFORM:-}" = "macos" ]; then
  if [ -d "/Applications/Brave Browser.app" ]; then
    log "Brave Browser installation complete."
    log_validation_details
    exit 0
  fi
  die "Brave install was attempted but /Applications/Brave Browser.app is still missing."
else
  if available brave-browser; then
    log "Brave Browser installation complete."
    log_validation_details
    exit 0
  fi
  die "Brave install was attempted but brave-browser is still not available."
fi
