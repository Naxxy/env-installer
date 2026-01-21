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
Installs NetBird and ensures the daemon/service is installed and running.

Notes:
  - This step does NOT run 'netbird up'.
  - Authentication must be completed manually.
EOF

log "$STEP_TITLE: starting"

# --------------------------------------------------------------------
# 3) Install (if needed)
# --------------------------------------------------------------------

if available netbird; then
  log "netbird already installed; continuing."
else
  case "${PLATFORM:-}" in
    macos)
      if ! available brew; then
        die "Homebrew is required to install netbird on macOS. Run the install-homebrew step first."
      fi
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
          log "Skipping: unsupported Linux distro for netbird (${DISTRO:-})."
          exit 0
          ;;
      esac
      ;;
    *)
      log "Skipping: unsupported platform for netbird (${PLATFORM:-})."
      exit 0
      ;;
  esac
fi

# --------------------------------------------------------------------
# 4) Validate install (invariant)
# --------------------------------------------------------------------

if ! available netbird; then
  die "netbird install was attempted but 'netbird' is still not in PATH."
fi

# --------------------------------------------------------------------
# 5) Ensure daemon/service is installed & running (idempotent)
# --------------------------------------------------------------------

netbird_service_is_running() {
  # Prefer NetBird's own service introspection if available.
  if netbird service status >/dev/null 2>&1; then
    netbird service status 2>/dev/null | grep -qi 'running' && return 0
  fi

  # Fallback: if the daemon is up, 'netbird status' usually succeeds.
  netbird status >/dev/null 2>&1
}

if netbird_service_is_running; then
  log "netbird service already running; skipping service install/start."
else
  log "Ensuring netbird service is installed and started"
  as_root netbird service install
  as_root netbird service start

  if netbird_service_is_running; then
    log "netbird service is now running."
  else
    die "netbird service install/start attempted but service does not appear to be running."
  fi
fi

# --------------------------------------------------------------------
# 6) Final notes
# --------------------------------------------------------------------

add_comments <<EOF
NetBird installed successfully.

Next steps (manual):
  netbird up

This will open a browser for authentication.
EOF

log "netbird installation complete (authentication pending)"
