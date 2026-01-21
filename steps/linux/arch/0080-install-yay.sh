#!/usr/bin/env sh
# Step: install-yay
#
# Ensures yay (AUR helper) is installed.
#
# Supported:
#   - Linux: arch, omarchy
#
# Skipped:
#   - macos
#   - proxmox
#   - non-Arch Linux

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

STEP_TITLE="${STEP_NAME:-install-yay}"
add_title "$STEP_TITLE"

add_comments <<EOF
Ensures yay (AUR helper) is installed.

Notes:
  - yay is only relevant on Arch-based systems.
  - Installation uses the official git-based bootstrap method.
EOF

log "$STEP_TITLE: starting"

# --------------------------------------------------------------------
# 3) Guards
# --------------------------------------------------------------------

if [ "${PLATFORM:-}" != "linux" ]; then
  log "Skipping: yay is only relevant on Linux."
  exit 0
fi

case "${DISTRO:-}" in
  arch|omarchy) : ;;
  *)
    log "Skipping: yay is only relevant on Arch-based Linux."
    exit 0
    ;;
esac

# --------------------------------------------------------------------
# 4) Idempotency check
# --------------------------------------------------------------------

if available yay; then
  log "yay already installed; skipping."
  exit 0
fi

# --------------------------------------------------------------------
# 5) Install
# --------------------------------------------------------------------

log "Installing yay (AUR helper)"

ensure_packages git base-devel

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run git clone https://aur.archlinux.org/yay.git "$TMP_DIR/yay"
(
  cd "$TMP_DIR/yay"
  run makepkg -si --noconfirm
)

# --------------------------------------------------------------------
# 6) Validate final state
# --------------------------------------------------------------------

if available yay; then
  log "yay installation complete."
else
  die "yay install attempted but 'yay' was not found in PATH."
fi
