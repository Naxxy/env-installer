#!/usr/bin/env sh
# Step: install-qutebrowser
#
# Installs qutebrowser (keyboard-driven web browser).
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

ROOT_DIR="$(
  CDPATH= cd -- "$(dirname -- "$0")/.." && pwd
)"

# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"

# --------------------------------------------------------------------
# 2) Logging preamble
# --------------------------------------------------------------------

require_logfile

STEP_TITLE="${STEP_NAME:-install-qutebrowser}"
add_title "$STEP_TITLE"

add_comments <<EOF
Installs qutebrowser using the system package manager.

Environment:
  PLATFORM = ${PLATFORM:-<unset>}
  DISTRO   = ${DISTRO:-<unset>}
  ARCH     = ${ARCH:-<unset>}
  PKG_MGR  = ${PKG_MGR:-<unset>}
EOF

log "$STEP_TITLE: starting"

# --------------------------------------------------------------------
# 3) Guards
# --------------------------------------------------------------------

if [ "${DISTRO:-}" = "proxmox" ]; then
  log "Skipping: qutebrowser is not intended for Proxmox hosts."
  exit 0
fi

# --------------------------------------------------------------------
# 4) Idempotency check
# --------------------------------------------------------------------

if available qutebrowser; then
  log "qutebrowser already installed; skipping."
  exit 0
fi

# --------------------------------------------------------------------
# 5) Install
# --------------------------------------------------------------------

case "${PKG_MGR:-none}" in
  brew)
    log "Installing qutebrowser via Homebrew"
    ensure_packages qutebrowser
    ;;
  pacman)
    log "Installing qutebrowser via pacman"
    ensure_packages qutebrowser
    ;;
  apt)
    log "Installing qutebrowser via apt"
    ensure_packages qutebrowser
    ;;
  *)
    log "Skipping: unsupported package manager for qutebrowser (PKG_MGR=${PKG_MGR:-none})."
    exit 0
    ;;
esac

# --------------------------------------------------------------------
# 6) Validate
# --------------------------------------------------------------------

if available qutebrowser; then
  log "qutebrowser installation complete."
else
  die "qutebrowser install attempted but binary not found."
fi
