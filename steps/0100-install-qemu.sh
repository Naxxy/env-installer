#!/usr/bin/env sh
# Step: install-qemu
#
# Installs QEMU (emulator/virtualizer tooling).
#
# Supported:
#   - macos (Homebrew)
#   - linux: arch, omarchy (pacman)
#   - linux: ubuntu, debian (apt)
#
# Skipped:
#   - proxmox (Proxmox ships/maintains its own QEMU packages; don't override them)

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

STEP_TITLE="${STEP_NAME:-install-qemu}"
add_title "$STEP_TITLE"

add_comments <<EOF
Installs QEMU.

Notes:
  - macOS installs via Homebrew: brew install qemu
  - Arch-based installs a headless-friendly meta package: qemu-base
  - Ubuntu/Debian installs: qemu-system + qemu-utils
  - Proxmox is skipped to avoid conflicting with Proxmox-maintained QEMU packages.
EOF

log "$STEP_TITLE: starting"

# --------------------------------------------------------------------
# Validation details (reusable)
# --------------------------------------------------------------------

PRIMARY_CMD="qemu-img"

log_validation_details() {
  {
    printf 'Validation details:\n'
    printf '  qemu-img path: %s\n' "$(command -v qemu-img 2>/dev/null || echo "<not found>")"
    printf '  qemu-img version/info: %s\n' "$(qemu-img --version 2>/dev/null || echo "<version check failed>")"
    printf '  qemu-system-* present: %s\n' "$(ls -1 "$(dirname "$(command -v qemu-img 2>/dev/null || echo /dev/null)")"/qemu-system-* 2>/dev/null | head -n 3 | tr '\n' ' ' | sed 's/[[:space:]]*$//' || echo "<none found>")"
  } | add_comments
}

# --------------------------------------------------------------------
# 3) Guards
# --------------------------------------------------------------------

if [ "${DISTRO:-}" = "proxmox" ]; then
  log "Skipping: Proxmox maintains its own QEMU packages; do not override via env-installer."
  exit 0
fi

# --------------------------------------------------------------------
# 4) Idempotency check
# --------------------------------------------------------------------

if available "$PRIMARY_CMD"; then
  log "QEMU already present; skipping."
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
    log "Installing QEMU via Homebrew"
    run brew install qemu
    ;;
  linux)
    case "${DISTRO:-}" in
      arch|omarchy)
        log "Installing QEMU via pacman (qemu-base)"
        ensure_packages qemu-base
        ;;
      ubuntu|debian)
        log "Installing QEMU via apt (qemu-system, qemu-utils)"
        ensure_packages qemu-system qemu-utils
        ;;
      *)
        log "Skipping: unsupported Linux distro for QEMU (${DISTRO:-})."
        exit 0
        ;;
    esac
    ;;
  *)
    log "Skipping: unsupported platform for QEMU (${PLATFORM:-})."
    exit 0
    ;;
esac

# --------------------------------------------------------------------
# 6) Validate final state
# --------------------------------------------------------------------

if available "$PRIMARY_CMD"; then
  log "QEMU installation complete."
  log_validation_details
else
  die "QEMU install attempted but '${PRIMARY_CMD}' was not found in PATH."
fi
