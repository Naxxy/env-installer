
#!/usr/bin/env sh
# Step: install-zed
#
# Installs Zed editor.
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
# 2) Logging preamble
# --------------------------------------------------------------------

require_logfile

STEP_TITLE="${STEP_NAME:-install-zed}"
add_title "$STEP_TITLE"

add_comments <<EOF
Installs Zed editor.

Notes:
  - macOS uses Homebrew cask: 'brew install --cask zed'
  - Linux uses the official installer: 'curl -f https://zed.dev/install.sh | sh'
EOF

log "$STEP_TITLE: starting"

PRIMARY_CMD="zed"

log_validation_details() {
  {
    printf 'Validation details:\n'
    printf '  zed path: %s\n' "$(command -v zed 2>/dev/null || echo "<not found>")"
    printf '  zed version/info: %s\n' "$(zed --version 2>/dev/null || echo "<version check failed>")"
    printf '  macOS app bundle: %s\n' "$( [ -d "/Applications/Zed.app" ] && echo "/Applications/Zed.app" || echo "<not found>" )"
  } | add_comments
}

# --------------------------------------------------------------------
# 3) Guards
# --------------------------------------------------------------------

if [ "${DISTRO:-}" = "proxmox" ]; then
  log "Skipping: Zed is a GUI app and is not intended for Proxmox hosts."
  exit 0
fi

# --------------------------------------------------------------------
# 4) Idempotency check
# --------------------------------------------------------------------

if available zed; then
  log "zed already installed; skipping."
  log_validation_details
  exit 0
fi

# macOS: Zed app bundle exists (Homebrew cask installs the .app)
if [ "${PLATFORM:-}" = "macos" ] && [ -d "/Applications/Zed.app" ]; then
  log "Zed.app already present; skipping."
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
    log "Installing Zed via Homebrew cask"
    run brew install --cask zed
    ;;
  linux)
    case "${DISTRO:-}" in
      arch|ubuntu|debian)
        log "Installing Zed via official install script"
        run sh -c "curl -f https://zed.dev/install.sh | sh"
        ;;
      *)
        log "Skipping: unsupported Linux distro for Zed (${DISTRO:-})."
        exit 0
        ;;
    esac
    ;;
  *)
    log "Skipping: unsupported platform for Zed (${PLATFORM:-})."
    exit 0
    ;;
esac

# --------------------------------------------------------------------
# 6) Validate final state
# --------------------------------------------------------------------

if available zed || ( [ "${PLATFORM:-}" = "macos" ] && [ -d "/Applications/Zed.app" ] ); then
  log "zed installation complete."
  log_validation_details
else
  die "zed install attempted but zed was not found in PATH (and Zed.app was not found on macOS)."
fi
