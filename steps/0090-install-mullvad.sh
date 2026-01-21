#!/usr/bin/env sh
# Step: install-mullvad
#
# Installs Mullvad VPN app.
#
# Supported:
#   - macOS
#   - Linux: ubuntu, debian
#   - Linux: arch (via AUR)
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
init_sudo

STEP_TITLE="${STEP_NAME:-install-mullvad}"
add_title "$STEP_TITLE"

add_comments <<EOF
Installs Mullvad VPN app.

Notes:
  - macOS uses Homebrew cask
  - Ubuntu/Debian uses official Mullvad apt repository
  - Arch uses unofficial AUR package (requires yay)
EOF

log "$STEP_TITLE: starting"

PRIMARY_CMD="mullvad"

log_validation_details() {
  {
    printf 'Validation details:\n'
    printf '  mullvad path: %s\n' "$(command -v mullvad 2>/dev/null || echo "<not found>")"
    printf '  mullvad version/info: %s\n' "$(mullvad version 2>/dev/null || echo "<version check failed>")"
    printf '  macOS app bundle: %s\n' "$( [ -d "/Applications/Mullvad VPN.app" ] && echo "/Applications/Mullvad VPN.app" || echo "<not found>" )"
    printf '  linux gui binary: %s\n' "$( [ -x "/opt/Mullvad VPN/mullvad-vpn" ] && echo "/opt/Mullvad VPN/mullvad-vpn" || echo "<not found>" )"
  } | add_comments
}

# --------------------------------------------------------------------
# 3) Guards
# --------------------------------------------------------------------

if [ "${DISTRO:-}" = "proxmox" ]; then
  log "Skipping: Mullvad is a GUI VPN app and is not intended for Proxmox hosts."
  exit 0
fi

# --------------------------------------------------------------------
# 4) Idempotency check
# --------------------------------------------------------------------

if available "$PRIMARY_CMD"; then
  log "Mullvad already installed; skipping."
  log_validation_details
  exit 0
fi

if [ "${PLATFORM:-}" = "macos" ] && [ -d "/Applications/Mullvad VPN.app" ]; then
  log "Mullvad VPN.app already present; skipping."
  log_validation_details
  exit 0
fi

# --------------------------------------------------------------------
# 5) Install
# --------------------------------------------------------------------

case "${PLATFORM:-}" in
  macos)
    if [ "${PKG_MGR:-none}" != "brew" ]; then
      log "Skipping: Homebrew not available."
      exit 0
    fi
    log "Installing Mullvad via Homebrew cask"
    run brew install --cask mullvad-vpn
    ;;
  linux)
    case "${DISTRO:-}" in
      ubuntu|debian)
        log "Installing Mullvad via official apt repository"
        as_root apt-get update -y
        as_root apt-get install -y curl ca-certificates

        if [ ! -f /usr/share/keyrings/mullvad-keyring.asc ]; then
          as_root sh -c 'curl -fsSLo /usr/share/keyrings/mullvad-keyring.asc https://repository.mullvad.net/deb/mullvad-keyring.asc'
        fi

        if [ ! -f /etc/apt/sources.list.d/mullvad.list ]; then
          as_root sh -c 'echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=$(dpkg --print-architecture)] https://repository.mullvad.net/deb/stable stable main" > /etc/apt/sources.list.d/mullvad.list'
        fi

        as_root apt-get update -y
        as_root apt-get install -y mullvad-vpn
        ;;
      arch)
        if ! available yay; then
          log "Skipping: Mullvad on Arch requires yay (run install-yay first)."
          exit 0
        fi
        log "Installing Mullvad via AUR (yay)"
        run yay -S --needed --noconfirm mullvad-vpn-bin
        ;;
      *)
        log "Skipping: unsupported Linux distro for Mullvad (${DISTRO:-})."
        exit 0
        ;;
    esac
    ;;
  *)
    log "Skipping: unsupported platform for Mullvad."
    exit 0
    ;;
esac

# --------------------------------------------------------------------
# 6) Validate final state
# --------------------------------------------------------------------

if available "$PRIMARY_CMD" || [ -d "/Applications/Mullvad VPN.app" ] || [ -x "/opt/Mullvad VPN/mullvad-vpn" ]; then
  log "Mullvad installation complete."
  log_validation_details
else
  log_validation_details
  die "Mullvad install attempted but it was not found in the expected locations."
fi
