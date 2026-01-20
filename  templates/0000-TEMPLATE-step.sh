#!/usr/bin/env sh
# Step: <HUMAN FRIENDLY TITLE>
#
# Filename convention: dddd-<name>.sh (e.g. 0020-install-yt-dlp.sh)
#
# This step is intended to be run *only* via install.sh, which is responsible for:
#   - Detecting PLATFORM, DISTRO, ARCH, DEVICE_ID, PKG_MGR.
#   - Parsing CLI flags (e.g. --debug).
#   - Initialising a per-run LOGFILE and passing it to this step.
#
# Assumptions (passed from install.sh):
#   - PLATFORM, DISTRO, ARCH, DEVICE_ID, PKG_MGR, LOGFILE, STEP_NAME are exported.
#   - DEBUG is exported and set to "1" or "0".
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
#   3) Guards (platform/distro/arch/device/pkg mgr)  [DELETE IF NOT NEEDED]
#   4) Idempotency check
#   5) Apply changes (install/configure)
#   6) Validate final state (+ validation details)
#
# Scope note:
#   - If this file lives under a scoped directory (e.g. steps/devices/<id>/),
#     it will usually override a more generic step with the same <name>.
#   - Keep the same "<name>" portion intentionally when you *want* an override.

set -eu

# --------------------------------------------------------------------
# 1) Load shared helpers
# --------------------------------------------------------------------
# Steps run in their own sh process, so we must source common.sh again.
#
# IMPORTANT:
#   Steps may live under nested scoped directories:
#     steps/<platform>/...
#     steps/<platform>/<distro>/...
#     steps/<platform>/arch/<arch>/...
#     steps/devices/<device-id>/...
#   So we cannot assume ".." gets us to repo root.
#
# Instead, walk upwards until we find lib/common.sh.

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

# Prefer the logical name install.sh provides (derived from filename).
# Fallback is useful when running manually during development.
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
  PLATFORM   = ${PLATFORM:-<unset>}
  DISTRO     = ${DISTRO:-<unset>}
  ARCH       = ${ARCH:-<unset>}
  DEVICE_ID  = ${DEVICE_ID:-<unset>}
  PKG_MGR    = ${PKG_MGR:-<unset>}
  DEBUG      = ${DEBUG:-0}
  LOGFILE    = ${LOGFILE:-<unset>}
EOF

log "$STEP_TITLE: starting (PLATFORM=$PLATFORM, DISTRO=$DISTRO, ARCH=$ARCH, DEVICE_ID=${DEVICE_ID:-unknown}, PKG_MGR=${PKG_MGR:-none})"

# --------------------------------------------------------------------
# Optional DEBUG diagnostics
# --------------------------------------------------------------------
# These diagnostics are emitted only when DEBUG=1.
# They must not affect control flow or stdout parsing.

if [ "${DEBUG:-0}" = "1" ]; then
  log_block <<EOF
DEBUG: step context
  STEP_NAME = ${STEP_NAME:-<unset>}
  SCRIPT    = $(basename "$0")
  LOCATION  = "$SCRIPT_DIR"
EOF
fi

# --------------------------------------------------------------------
# Validation details (reusable block)
# --------------------------------------------------------------------
# State-agnostic diagnostic output to help debug PATH / wrong binary issues.
# Safe to delete if you prefer quieter logs.

PRIMARY_CMD="<primary-command-or-check>"

log_validation_details() {
  # Appends validation details into the shared LOGFILE for this run.
  #
  # NOTE: PRIMARY_CMD is a template placeholder by default. We guard the
  # command invocation so the template doesn't try to execute "<primary...>".
  if [ "$PRIMARY_CMD" = "<primary-command-or-check>" ]; then
    printf '%s\n' "Validation details: PRIMARY_CMD not set (template placeholder)." | add_comments
    return 0
  fi

  {
    printf 'Validation details:\n'
    printf '  %s path: %s\n' "$PRIMARY_CMD" "$(command -v "$PRIMARY_CMD" 2>/dev/null || echo "<not found>")"
    printf '  %s version/info: %s\n' "$PRIMARY_CMD" "$("$PRIMARY_CMD" --version 2>/dev/null || echo "<version check failed>")"
  } | add_comments
}

# --------------------------------------------------------------------
# 3) Guards / requirements (PLATFORM / DISTRO / ARCH / DEVICE_ID / PKG_MGR)
#    DELETE THIS SECTION IF NOT NEEDED
# --------------------------------------------------------------------
# Guards are "safety rails". Even if this script is in a scoped directory,
# keep guards if the step is risky or device-specific.
#
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

# Example: device specific
# (Useful even inside steps/devices/<device-id>/ as a defensive check.)
# if ! require_device "thinkpad-x240"; then
#   log "Skipping: this step only applies to device thinkpad-x240 (got '${DEVICE_ID:-unknown}')."
#   exit 0
# fi
#
# Alternative hard-fail version:
# require_device "thinkpad-x240" || die "This step is only for device thinkpad-x240."

# Example: require a package manager
# if [ "${PKG_MGR:-none}" = "none" ]; then
#   warn "No supported package manager detected."
#   die "Cannot install <THING> automatically."
# fi

# Example: attempt ensure_packages, skip if it cannot be used
# (ensure_packages returns non-zero when PKG_MGR is none/unknown)
# if ! ensure_packages <pkg-name> <pkg-name-2>; then
#   log "Skipping: ensure_packages could not install <THING> (PKG_MGR=${PKG_MGR:-none})."
#   exit 0
# fi

# --------------------------------------------------------------------
# 4) Idempotency check (desired state)
# --------------------------------------------------------------------
# Replace this with the correct desired-state check(s) for <THING>.
#
# Common patterns:
#   - command exists: available toolname
#   - config file exists with desired content
#   - service enabled/active
#   - a symlink points to expected target
#
# Keep idempotency checks cheap and predictable.

# Example: command exists
# if available "$PRIMARY_CMD"; then
#   log "<THING> already installed; skipping."
#   log_validation_details
#   exit 0
# fi

# TODO: implement idempotency check for <THING>
if available "$PRIMARY_CMD"; then
  log "<THING> already present; skipping."
  log_validation_details
  exit 0
fi

# --------------------------------------------------------------------
# 5) Apply changes (install / configure)
# --------------------------------------------------------------------
# Prefer ensure_packages for package installs.
# Use run / as_root for custom logic.
#
# Keep this section small. If it grows large, extract helpers into lib/
# and keep the step as orchestration.

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
# Always validate the desired state after applying changes.
# This prevents silent partial installs.

if available "$PRIMARY_CMD"; then
  log "<THING> installation/configuration complete."
  log_validation_details
else
  die "<THING> was attempted but is still not in the expected state."
fi
