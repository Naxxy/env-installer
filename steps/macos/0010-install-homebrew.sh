#!/usr/bin/env sh
# Step: install-homebrew
#
# This step is intended to be run *only* via install.sh, which is responsible for:
#   - Detecting PLATFORM, DISTRO, ARCH, PKG_MGR.
#   - Initialising a per-run LOGFILE and passing it to this step.
#
# Assumptions (passed from install.sh):
#   - PLATFORM, DISTRO, ARCH, PKG_MGR, LOGFILE, STEP_NAME, DEBUG are exported.
#   - LOGFILE already exists and is writable.
#
# Responsibilities:
#   - Log a clear step header + description into LOGFILE.
#   - Ensure Homebrew is installed on macOS.
#   - Be idempotent (no changes if already installed).

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

  if [ "$ROOT_DIR" = "/" ]; then
    echo "[ERR] Could not locate repo root (lib/common.sh not found)." >&2
    exit 1
  fi
done

# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"

# --------------------------------------------------------------------
# 2) Logging preamble for this step
# --------------------------------------------------------------------

require_logfile

STEP_TITLE="${STEP_NAME:-install-homebrew}"

add_title "$STEP_TITLE"
add_comments <<EOF
This step ensures that Homebrew is installed on macOS systems.

Behaviour:
  - If Homebrew is already present in PATH, no action is taken (idempotent).
  - If Homebrew is missing, it is installed using the official installer.
  - Non-macOS platforms are skipped cleanly.

Environment snapshot:
  PLATFORM = ${PLATFORM:-<unset>}
  DISTRO   = ${DISTRO:-<unset>}
  ARCH     = ${ARCH:-<unset>}
  PKG_MGR  = ${PKG_MGR:-<unset>}
  DEBUG    = ${DEBUG:-false}
EOF

log "$STEP_TITLE: starting (PLATFORM=$PLATFORM, ARCH=$ARCH)"

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
# 3) Guards / requirements
# --------------------------------------------------------------------

if [ "${PLATFORM:-}" != "macos" ]; then
  log "Skipping: Homebrew only applies to macOS."
  exit 0
fi

# --------------------------------------------------------------------
# 4) Idempotency check
# --------------------------------------------------------------------

if available brew; then
  log "Homebrew already present; skipping."
  [ "${DEBUG:-false}" = "true" ] && log_validation_details
  exit 0
fi

# --------------------------------------------------------------------
# 5) Apply changes (install)
# --------------------------------------------------------------------

log "Homebrew not found; installing via official installer."

HTTP_CLIENT="$(first_of curl wget || true)"
if [ -z "$HTTP_CLIENT" ]; then
  die "No HTTP client (curl or wget) available to install Homebrew."
fi

log_block <<EOF
Running Homebrew installer using:
  HTTP client: $HTTP_CLIENT
  Architecture: $ARCH
EOF

if [ "$HTTP_CLIENT" = "curl" ]; then
  run /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  run /bin/bash -c \
    "$(wget -qO- https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# --------------------------------------------------------------------
# 6) Validate final state
# --------------------------------------------------------------------

if available brew; then
  log "Homebrew installation complete."
  log_validation_details
else
  die "Homebrew installation was attempted but brew is still not available."
fi
