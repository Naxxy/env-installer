#!/usr/bin/env sh
# Step: install-netbird
#
# Installs NetBird (mesh VPN / WireGuard-based networking).
#
# Supported:
#   - macOS
#   - Linux: arch, ubuntu, proxmox

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

STEP_TITLE="${STEP_NAME:-install-netbird}"
add_title "$STEP_TITLE"

add_comments <<EOF
Installs NetBird and ensures the daemon is installed and running.

Notes:
  - This step does NOT run 'netbird up'.
  - Authentication must be completed manually.
EOF

log "$STEP_TITLE: starting"

# --------------------------------------------------------------------
# 3) Idempotency check
# --------------------------------------------------------------------

if available netbird; then
  log "netbird already installed; ensuring service is running."
else
  case "${PLATFORM:-}" in
    macos)
      log "Installing netbird via Homebrew tap"
      run brew tap netbirdio/tap
      run brew install netbirdio/tap/netbird
      ;;
    linux)
      case "${DISTRO:-}" in
        arch)
          log "Installing netbird via pacman"
          ensure_packages netbird
          ;;
        ubuntu|debian|proxmox)
          log "Installing netbird via official installer"
          run sh -c "curl -fsSL https://pkgs.netbird.io/install.sh | sh"
          ;;
        *)
          log "Skipping: unsupported Linux distro (${DISTRO:-})"
          exit 0
          ;;
      esac
      ;;
    *)
      log "Skipping: unsupported platform (${PLATFORM:-})"
      exit 0
      ;;
  esac
fi

# --------------------------------------------------------------------
# 4) Ensure daemon is installed & running
# --------------------------------------------------------------------

if available netbird; then
  log "Ensuring netbird service is installed and started"
  as_root netbird service install || true
  as_root netbird service start || true
else
  die "netbird binary not found after install"
fi

# --------------------------------------------------------------------
# 5) Final notes
# --------------------------------------------------------------------

add_comments <<EOF
NetBird installed successfully.

Next steps (manual):
  netbird up

This will open a browser for authentication.
EOF

log "netbird installation complete (authentication pending)"
