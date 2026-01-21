#!/usr/bin/env sh
# Step: install-mpv
#
# Installs mpv media player.
#
# Supported:
#   - macOS (Homebrew formula; no .app bundle)
#   - Linux: arch, omarchy (pacman)
#   - Linux: ubuntu, debian (apt)
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
# 2) Logging preamble
# --------------------------------------------------------------------

require_logfile

STEP_TITLE="${STEP_NAME:-install-mpv}"
add_title "$STEP_TITLE"

add_comments <<EOF
Installs mpv media player.

Notes:
  - macOS installs via Homebrew formula (no application bundle).
  - mpv.io recommends newer builds than stock packages for some distros; this step
    uses the standard package manager for simplicity.
EOF

log "$STEP_TITLE: starting"

# --------------------------------------------------------------------
# Validation details (reusable)
# --------------------------------------------------------------------

PRIMARY_CMD="mpv"

log_validation_details() {
  {
    printf 'Validation details:\n'
    printf '  mpv path: %s\n' "$(command -v mpv 2>/dev/null || echo "<not found>")"
    printf '  mpv version/info: %s\n' "$(mpv --version 2>/dev/null | head -n 1 || echo "<version check failed>")"
  } | add_comments
}

# --------------------------------------------------------------------
# 3) Guards
# --------------------------------------------------------------------

if [ "${DISTRO:-}" = "proxmox" ]; then
  log "Skipping: mpv is not intended for Proxmox hosts."
  exit 0
fi

# --------------------------------------------------------------------
# 4) Idempotency check
# --------------------------------------------------------------------

if available "$PRIMARY_CMD"; then
  log "mpv already installed; skipping."
  log_validation_details
  exit 0
fi

# --------------------------------------------------------------------
# 5) Install
# --------------------------------------------------------------------

case "${PLATFORM:-}" in
  macos)
    if [ "${PKG_MGR:-none}" != "brew" ]; then
      log "Skipping: Homebrew not available (PKG_MGR=${PKG_MGR:-none})."
      exit 0
    fi
    log "Installing mpv via Homebrew"
    run brew install mpv
    ;;

  linux)
    case "${DISTRO:-}" in
      arch|omarchy)
        log "Installing mpv via pacman"
        ensure_packages mpv
        ;;
      ubuntu|debian)
        log "Installing mpv via apt"
        ensure_packages mpv
        ;;
      *)
        log "Skipping: unsupported Linux distro for mpv (${DISTRO:-})."
        exit 0
        ;;
    esac
    ;;

  *)
    log "Skipping: unsupported platform for mpv (${PLATFORM:-})."
    exit 0
    ;;
esac

# --------------------------------------------------------------------
# 6) Validate final state
# --------------------------------------------------------------------

if available "$PRIMARY_CMD"; then
  log "mpv installation complete."
  log_validation_details
else
  log_validation_details
  die "mpv install attempted but 'mpv' was not found in PATH."
fi
