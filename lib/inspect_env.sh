#!/usr/bin/env sh
# env-installer: environment & device inspector
#
# Purpose:
#   A small, safe script you can run to print what env-installer would detect:
#     - Which ENV_INSTALLER_* overrides are set
#     - What platform / arch / distro / pkg manager / device id resolve to
#     - Which log directory would be used (without creating logs)
#
# Usage:
#   sh lib/inspect_env.sh
#
# Notes:
#   - This script is read-only: it does not install anything, does not write logs,
#     and does not require sudo.
#   - It relies on lib/common.sh for detection so results match install.sh.

set -eu

# Resolve repo root as parent of lib/
ROOT_DIR="$(
  CDPATH= cd -- "$(dirname -- "$0")/.." && pwd
)"

# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"

# ---------------------------
# Pretty output helpers
# ---------------------------

h1() {
  printf '────────────────────────────────────────────────────────\n'
  printf ' %s\n' "$1"
  printf '────────────────────────────────────────────────────────\n'
}

kv() {
  key="$1"
  val="${2:-}"
  if [ -z "$val" ]; then
    val="<unset>"
  fi
  printf '%-28s %s\n' "$key:" "$val"
}

# ---------------------------
# Compute "effective" values
# ---------------------------

compute_effective_log_dir() {
  # Mirrors install.sh log dir selection logic, but does not create directories.
  if [ -n "${ENV_INSTALLER_LOG_DIR:-}" ]; then
    printf '%s\n' "$ENV_INSTALLER_LOG_DIR"
  elif [ -n "${XDG_STATE_HOME:-}" ]; then
    printf '%s\n' "$XDG_STATE_HOME/env-installer"
  else
    printf '%s\n' "$HOME/.local/state/env-installer"
  fi
}

# ---------------------------
# Main
# ---------------------------

main() {
  h1 "env-installer inspector"

  # Show relevant environment overrides first (what might affect detection)
  h1 "ENV overrides (what you may have set)"
  kv "ENV_INSTALLER_LOG_DIR" "${ENV_INSTALLER_LOG_DIR:-}"
  kv "ENV_INSTALLER_DEVICE_ID" "${ENV_INSTALLER_DEVICE_ID:-}"
  kv "ENV_INSTALLER_DEVICE" "${ENV_INSTALLER_DEVICE:-}"
  kv "XDG_STATE_HOME" "${XDG_STATE_HOME:-}"
  kv "SHELL" "${SHELL:-}"
  kv "HOME" "${HOME:-}"

  # Run the same detection functions as install.sh
  h1 "Detected values (what common.sh resolves)"
  detect_platform
  detect_arch
  detect_distro
  detect_pkg_manager
  detect_device_id

  kv "PLATFORM" "${PLATFORM:-}"
  kv "ARCH" "${ARCH:-}"
  kv "DISTRO" "${DISTRO:-}"
  kv "PKG_MGR" "${PKG_MGR:-}"
  kv "DEVICE_ID" "${DEVICE_ID:-}"

  # Also show the effective log dir based on the same rules as install.sh
  h1 "Derived paths (based on current env)"
  kv "Repo root" "$ROOT_DIR"
  kv "Effective log dir" "$(compute_effective_log_dir)"

  printf '\n'
}

main "$@"
