
#!/usr/bin/env sh
# Step: <HUMAN FRIENDLY TITLE>
#
# Filename convention: dddd-<name>.sh (e.g. 0020-install-yt-dlp.sh)
#
# This step is intended to be run *only* via install.sh, which is responsible for:
#   - Detecting PLATFORM, DISTRO, ARCH, PKG_MGR.
#   - Initialising a per-run LOGFILE and passing it to this step.
#
# Assumptions (passed from install.sh):
#   - PLATFORM, DISTRO, ARCH, PKG_MGR, LOGFILE, STEP_NAME are exported.
#   - LOGFILE already exists and is writable.
#
# Responsibilities:
#   - Log a clear step header + description into LOGFILE.
#   - Ensure <THING> is installed/configured.
#   - Be idempotent (no changes if already in desired state).
#
# Structure:
#   1) Safety checks + common.sh import
#   2) Logfile header + intent
#   3) Guards (platform/distro/arch/pkg mgr)  [DELETE IF NOT NEEDED]
#   4) Idempotency check
#   5) Apply changes (install/configure)
#   6) Validate final state (+ validation details)

set -eu

# --------------------------------------------------------------------
# 1) Load shared helpers
# --------------------------------------------------------------------
# Steps run in their own sh process, so we must source common.sh again.

ROOT_DIR="$(
  CDPATH= cd -- "$(dirname -- "$0")/.." && pwd
)"

# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"

# --------------------------------------------------------------------
# 2) Logging preamble for this step
# --------------------------------------------------------------------

require_logfile

STEP_TITLE="${STEP_NAME:-<dddd-step-name>}"

add_title "$STEP_TITLE"
add_comments <<EOF
This step ensures that <THING> is installed/configured on the current system.

Behaviour:
  - If <DESIRED STATE CHECK> is already true, no changes are made (idempotent).
  - Otherwise, installation/configuration is performed.
  - If the environment is unsupported, the step will either:
      - skip cleanly (exit 0), or
      - fail loudly (exit 1),
    depending on how guards are configured.

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
# State-agnostic diagnostic output to help debug PATH / wrong binary issues.
# Safe to delete if you prefer quieter logs.

VALIDATION_DETAILS=$(cat <<EOF
Validation details:
  <THING> path: $(command -v <primary-command-or-check> 2>/dev/null || echo "<not found>")
  <THING> version/info: $(<primary-command-or-check> --version 2>/dev/null || echo "<version check failed>")
EOF
)

log_validation_details() {
  printf '%s\n' "$VALIDATION_DETAILS" | add_comments
}

# --------------------------------------------------------------------
# 3) Guards / requirements (PLATFORM / DISTRO / ARCH / PKG_MGR)
#    DELETE THIS SECTION IF NOT NEEDED
# --------------------------------------------------------------------
# Choose one of these patterns:
#
# HARD FAIL:
#   die "This step only supports ..."
#
# SOFT SKIP (recommended for optional tooling):
#   log "Skipping: ..."; exit 0

# Example: macOS only
# if [ "${PLATFORM:-}" != "macos" ]; then
#   log "Skipping: <THING> only applies to macOS."
#   exit 0
# fi

# Example: Linux distro specific
# if [ "${PLATFORM:-}" != "linux" ] || [ "${DISTRO:-}" != "arch" ]; then
#   log "Skipping: <THING> only applies to Arch Linux."
#   exit 0
# fi

# Example: architecture specific
# case "${ARCH:-}" in
#   x86_64|aarch64) ;;
#   *)
#     log "Skipping: unsupported arch '$ARCH' for <THING>."
#     exit 0
#     ;;
# esac

# Example: require a package manager
# if [ "${PKG_MGR:-none}" = "none" ]; then
#   warn "No supported package manager detected."
#   die "Cannot install <THING> automatically."
# fi

# --------------------------------------------------------------------
# 4) Idempotency check (desired state)
# --------------------------------------------------------------------
# Replace this with the correct desired-state check(s).

# Example: command exists
# if available <command>; then
#   log "<THING> already installed; skipping."
#   log_validation_details
#   exit 0
# fi

# TODO: implement idempotency check for <THING>
if available <primary-command-or-check>; then
  log "<THING> already present; skipping."
  log_validation_details
  exit 0
fi

# --------------------------------------------------------------------
# 5) Apply changes (install / configure)
# --------------------------------------------------------------------
# Prefer ensure_packages for package installs.
# Use run / as_root for custom logic.

case "${PKG_MGR:-none}" in
  apt)
    log "Installing <THING> via apt (ensure_packages ...)"
    # ensure_packages <pkg-name>
    ;;
  pacman)
    log "Installing <THING> via pacman (ensure_packages ...)"
    # ensure_packages <pkg-name>
    ;;
  brew)
    log "Installing <THING> via Homebrew (ensure_packages ...)"
    # ensure_packages <pkg-name>
    ;;
  none)
    warn "No supported package manager detected (PKG_MGR=none)."
    die "Cannot install <THING> automatically; install it manually."
    ;;
  *)
    warn "Unknown PKG_MGR='${PKG_MGR:-}'"
    die "Cannot install <THING> with unknown package manager."
    ;;
esac

# --------------------------------------------------------------------
# 6) Validate final state (+ validation details)
# --------------------------------------------------------------------

if available <primary-command-or-check>; then
  log "<THING> installation/configuration complete."
  log_validation_details
else
  die "<THING> was attempted but is still not in the expected state."
fi
