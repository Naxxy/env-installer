#!/usr/bin/env sh
# Step: install-yt-dlp
#
# Installs yt-dlp.
#
# Supported:
#   - macOS
#   - Linux: arch, omarchy, ubuntu, debian
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

STEP_TITLE="${STEP_NAME:-install-yt-dlp}"
add_title "$STEP_TITLE"

add_comments <<EOF
Installs yt-dlp.

Notes:
  - This step prefers OS package managers (brew/apt/pacman) for simplicity.
  - If you want the upstream standalone binary instead, add a dedicated step
    that installs to ~/.local/bin and manages upgrades explicitly.
EOF

log "$STEP_TITLE: starting"

# --------------------------------------------------------------------
# Validation details (reusable)
# --------------------------------------------------------------------

PRIMARY_CMD="yt-dlp"

log_validation_details() {
  {
    printf 'Validation details:\n'
    printf '  yt-dlp path: %s\n' "$(command -v yt-dlp 2>/dev/null || echo "<not found>")"
    printf '  yt-dlp version/info: %s\n' "$(yt-dlp --version 2>/dev/null || echo "<version check failed>")"
  } | add_comments
}

# --------------------------------------------------------------------
# 3) Guards
# --------------------------------------------------------------------

if [ "${DISTRO:-}" = "proxmox" ]; then
  log "Skipping: yt-dlp is not intended for Proxmox hosts."
  exit 0
fi

# --------------------------------------------------------------------
# 4) Idempotency check
# --------------------------------------------------------------------

if available "$PRIMARY_CMD"; then
  log "yt-dlp already installed; skipping."
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
    log "Installing yt-dlp via Homebrew"
    run brew install yt-dlp
    ;;

  linux)
    case "${DISTRO:-}" in
      arch|omarchy)
        log "Installing yt-dlp via pacman"
        ensure_packages yt-dlp
        ;;
      ubuntu|debian)
        log "Installing yt-dlp via apt"
        ensure_packages yt-dlp
        ;;
      *)
        log "Skipping: unsupported Linux distro for yt-dlp (${DISTRO:-})."
        exit 0
        ;;
    esac
    ;;

  *)
    log "Skipping: unsupported platform for yt-dlp (${PLATFORM:-})."
    exit 0
    ;;
esac

# --------------------------------------------------------------------
# 6) Validate final state
# --------------------------------------------------------------------

if available "$PRIMARY_CMD"; then
  log "yt-dlp installation complete."
  log_validation_details
else
  log_validation_details
  die "yt-dlp install attempted but 'yt-dlp' was not found in PATH."
fi
