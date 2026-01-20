#!/usr/bin/env sh
# Step: install-docker
#
# Installs Docker Engine (and Docker Desktop on macOS).
#
# Supported:
#   - macOS (Homebrew)
#   - Arch Linux
#   - Ubuntu / Debian
#
# Explicitly skipped:
#   - Proxmox hosts

set -eu

# --------------------------------------------------------------------
# 1) Load shared helpers
# --------------------------------------------------------------------

SCRIPT_DIR="$(
  CDPATH= cd -- "$(dirname -- "$0")" && pwd
)"

ROOT_DIR="$SCRIPT_DIR"
while [ ! -f "$ROOT_DIR/lib/common.sh" ]; do
  ROOT_DIR="$(
    CDPATH= cd -- "$ROOT_DIR/.." && pwd
  )"
  [ "$ROOT_DIR" != "/" ] || {
    echo "[ERR] Could not locate repo root (lib/common.sh not found)." >&2
    exit 1
  }
done

# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"

# --------------------------------------------------------------------
# 2) Logging preamble
# --------------------------------------------------------------------

require_logfile

STEP_TITLE="${STEP_NAME:-install-docker}"

add_title "$STEP_TITLE"
add_comments <<EOF
Installs Docker on supported systems.

Behaviour:
  - Idempotent: if Docker is already installed, no changes are made.
  - Skips Proxmox hosts by default.
  - Uses native package managers where possible.
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
  LOCATION  = $SCRIPT_DIR
EOF
fi

# --------------------------------------------------------------------
# 3) Guards / requirements
# --------------------------------------------------------------------

# Safety: never install Docker directly on Proxmox hosts
if [ "${DISTRO:-}" = "proxmox" ]; then
  log "Skipping: Docker is not installed on Proxmox hosts by default."
  exit 0
fi

# --------------------------------------------------------------------
# 4) Idempotency check
# --------------------------------------------------------------------

PRIMARY_CMD="docker"

if available docker; then
  log "Docker already installed; skipping."
  exit 0
fi

# --------------------------------------------------------------------
# 5) Apply changes
# --------------------------------------------------------------------

case "${PLATFORM:-}" in
  macos)
    log "Installing Docker Desktop via Homebrew"
    ensure_packages --cask docker
    ;;
  linux)
    case "${DISTRO:-}" in
      arch)
        log "Installing Docker via pacman"
        ensure_packages docker
        ;;
      ubuntu|debian)
        log "Installing Docker via apt"
        ensure_packages docker.io
        ;;
      *)
        log "Skipping: unsupported Linux distro '$DISTRO' for Docker install."
        exit 0
        ;;
    esac
    ;;
  *)
    log "Skipping: unsupported platform '$PLATFORM' for Docker install."
    exit 0
    ;;
esac

# --------------------------------------------------------------------
# 6) Validate final state
# --------------------------------------------------------------------

if available docker; then
  log "Docker installation complete."
else
  die "Docker was attempted but is still not available."
fi
