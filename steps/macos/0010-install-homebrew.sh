#!/usr/bin/env sh
# Step: Install Homebrew (macOS)
#
# This step is intended to be run *only* via install.sh, which is responsible for:
#   - Detecting PLATFORM, DISTRO, ARCH, PKG_MGR.
#   - Initialising a per-run LOGFILE and passing it to this step.
#
# Assumptions (passed from install.sh):
#   - PLATFORM, DISTRO, ARCH, PKG_MGR, LOGFILE, STEP_NAME are exported.
#   - LOGFILE already exists and is writable.

set -eu

# --------------------------------------------------------------------
# 1) Load shared helpers
# --------------------------------------------------------------------

ROOT_DIR="$(
  CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd
)"

# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"

# --------------------------------------------------------------------
# 2) Logging preamble for this step
# --------------------------------------------------------------------

require_logfile

STEP_TITLE="${STEP_NAME:-install-homebrew}"

add_title "$STEP_TITLE"
add_comments <<EOF
This step ensures that Homebrew (brew) is installed on macOS.

Behaviour:
  - If brew is already available, no changes are made (idempotent).
  - Otherwise, Homebrew is installed using the official installer script.

Environment snapshot (as passed from install.sh):
  PLATFORM = ${PLATFORM:-<unset>}
  DISTRO   = ${DISTRO:-<unset>}
  ARCH     = ${ARCH:-<unset>}
  PKG_MGR  = ${PKG_MGR:-<unset>}
  LOGFILE  = ${LOGFILE:-<unset>}
EOF

log "$STEP_TITLE: starting (PLATFORM=$PLATFORM, DISTRO=$DISTRO, ARCH=$ARCH, PKG_MGR=${PKG_MGR:-none})"

# --------------------------------------------------------------------
# Validation details (reusable block)
# --------------------------------------------------------------------

VALIDATION_DETAILS=$(cat <<EOF
Validation details:
  brew path: $(command -v brew 2>/dev/null || echo "<not found>")
  brew version: $(brew --version 2>/dev/null | head -n 1 || echo "<version check failed>")
EOF
)

log_validation_details() {
  printf '%s\n' "$VALIDATION_DETAILS" | add_comments
}

# --------------------------------------------------------------------
# 3) Guards / requirements (PLATFORM / DISTRO / ARCH / PKG_MGR)
# --------------------------------------------------------------------

if [ "${PLATFORM:-}" != "macos" ]; then
  log "Skipping: Homebrew only applies to macOS."
  exit 0
fi

# --------------------------------------------------------------------
# 4) Idempotency check (desired state)
# --------------------------------------------------------------------

if available brew; then
  log "Homebrew already present; skipping."
  log_validation_details
  exit 0
fi

# --------------------------------------------------------------------
# 5) Apply changes (install / configure)
# --------------------------------------------------------------------
# Install Homebrew using the official installer.
# Note: Homebrew install may prompt for sudo when it needs to create directories.

HTTP_CLIENT="$(first_of curl wget || true)"
if [ -z "$HTTP_CLIENT" ]; then
  die "No HTTP client found (need curl or wget) to install Homebrew."
fi

log "Installing Homebrew using official installer (HTTP client: $HTTP_CLIENT)..."

case "$HTTP_CLIENT" in
  curl)
    run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ;;
  wget)
    run /bin/bash -c "$(wget -qO- https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ;;
  *)
    die "Unexpected HTTP client '$HTTP_CLIENT'"
    ;;
esac

# Ensure brew is available in this non-interactive shell for validation.
# Homebrew typically installs into:
#   - /opt/homebrew/bin (Apple Silicon)
#   - /usr/local/bin   (Intel)
if ! available brew; then
  if [ -x /opt/homebrew/bin/brew ]; then
    PATH="/opt/homebrew/bin:$PATH"
    export PATH
  elif [ -x /usr/local/bin/brew ]; then
    PATH="/usr/local/bin:$PATH"
    export PATH
  fi
fi

# --------------------------------------------------------------------
# 6) Validate final state (+ validation details)
# --------------------------------------------------------------------

if available brew; then
  log "Homebrew installation complete."
  log_validation_details
else
  die "Homebrew installation attempted but brew is still not in PATH."
fi
