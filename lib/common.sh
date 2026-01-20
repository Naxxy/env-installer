#!/usr/bin/env sh
# Common helper functions for env-installer
# Intent: keep each helper small and obvious, so behaviour is easy to verify.
# These helpers are meant to be sourced from individual install scripts, e.g.:
#
#   . "$ROOT_DIR/lib/common.sh"
#
# Typical flow inside an installer:
#   - detect_platform / detect_arch / detect_distro / detect_pkg_manager / detect_device_id
#   - init_sudo
#   - (optionally) set up LOGFILE and write a title + description block
#   - use ensure_packages / as_root / log / warn / die as needed

set -eu

# ---- logging / errors -------------------------------------------------------

_emit_log_line() {
  # $1 = level (INFO | WARN | ERR)
  # $2 = message
  _level="$1"
  _msg="$2"

  # Always emit to terminal
  printf '[%s] %s\n' "$_level" "$_msg"

  # Also emit to LOGFILE if it exists and is a regular file
  if [ -n "${LOGFILE:-}" ] && [ -f "$LOGFILE" ]; then
    printf '[%s] %s\n' "$_level" "$_msg" >>"$LOGFILE"
  fi
}

log() {
  # Simple structured log to stdout.
  # usage:
  #   log "Installing Homebrew..."
  _emit_log_line "INFO" "$*"
}

warn() {
  # Warning to stderr (non-fatal).
  # usage:
  #   warn "Homebrew not found; attempting fresh install."
  _emit_log_line "WARN" "$*" >&2
}

die() {
  # Fatal error: message to stderr and exit non-zero.
  # Call this when the script cannot safely continue.
  # usage:
  #   die "Unsupported platform: $PLATFORM"
  _emit_log_line "ERR" "$*" >&2
  exit 1
}

# ---- simple file-based logging helpers -------------------------------------

require_logfile() {
  # Ensures LOGFILE is defined and points to an existing regular file.
  # This is used by add_title / add_comments so that they fail loudly if
  # the caller forgot to initialise the log file.
  #
  # Typical pattern in a script:
  #   LOGFILE="$HOME/.env-installer/logs/0010-install-homebrew.log"
  #   mkdir -p "$(dirname "$LOGFILE")"
  #   : >"$LOGFILE"   # truncate or create
  #
  # After that, add_title / add_comments are safe to call.
  if [ -z "${LOGFILE:-}" ]; then
    die "LOGFILE is not set; cannot write log."
  fi

  if [ ! -f "$LOGFILE" ]; then
    die "LOGFILE '$LOGFILE' does not exist; create it before logging."
  fi
}

add_title() {
  # Append a visual "title block" to LOGFILE.
  #
  # If no argument is provided, it defaults to the current script's basename.
  # This is useful for creating a standard header per installer script, e.g.:
  #
  #   # in 0010-install-homebrew.sh
  #   LOGFILE="$HOME/.env-installer/logs/0010-install-homebrew.log"
  #   mkdir -p "$(dirname "$LOGFILE")"
  #   : >"$LOGFILE"
  #   add_title
  #
  # which will produce:
  #
  #   ===================================
  #   0010-install-homebrew.sh
  #   ===================================
  #
  require_logfile

  _title="${1:-$(basename "$0")}"
  {
    printf '===================================\n'
    printf '%s\n' "$_title"
    printf '===================================\n\n'
  } >>"$LOGFILE"
}

add_comments() {
  # Append a free-form, multi-line comment block to LOGFILE, reading from stdin.
  # This is designed to pair nicely with a here-document:
  #
  #   add_comments <<'EOF'
  #   This script ensures that Homebrew is installed and up to date.
  #   It will only run if the current operating system is Darwin / macOS.
  #   EOF
  #
  # This gives you a lightweight way to document intent, caveats, and
  # behaviour directly into the log file, next to the title block.
  require_logfile
  cat >>"$LOGFILE"
}

# ---- command helpers --------------------------------------------------------

available() {
  # Returns success if the given command exists in PATH.
  #
  # usage:
  #   if available git; then
  #     log "git found"
  #   fi
  command -v "${1:?}" >/dev/null 2>&1
}

first_of() {
  # Returns the first available command name from the arguments.
  # This is useful when you can work with multiple tools (curl/wget, sudo/doas).
  #
  # usage:
  #   HTTP_CLIENT=$(first_of curl wget) || die "No HTTP client found."
  #
  for c in "$@"; do
    if available "$c"; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

run() {
  # Execute a command with a one-off 'set -x' for visibility.
  # This makes it easy to see what is being run without enabling global tracing.
  #
  # usage:
  #   run apt-get update -y
  (
    set -x
    "$@"
  )
}

# ---- platform / distro / package manager detection -------------------------

detect_platform() {
  # Sets PLATFORM to one of: linux, macos.
  # Call this early in your script so later logic can branch on PLATFORM.
  #
  # usage:
  #   detect_platform
  #   [ "$PLATFORM" = "macos" ] && ...
  case "$(uname -s)" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
    *) die "Unsupported platform: $(uname -s)" ;;
  esac
}

detect_arch() {
  # Sets ARCH to a simple name (x86_64, aarch64) or raw uname -m.
  # This is useful when downloading architecture-specific binaries.
  #
  # usage:
  #   detect_arch
  #   case "$ARCH" in x86_64) ... ;; esac
  case "$(uname -m)" in
    x86_64 | amd64) ARCH="x86_64" ;;
    aarch64 | arm64) ARCH="aarch64" ;;
    *)
      ARCH="$(uname -m)"
      warn "Unknown architecture $(uname -m); using raw value: $ARCH"
      ;;
  esac
}

detect_distro() {
  # Sets DISTRO to a simple identifier:
  #   - ubuntu, debian, arch, proxmox, omarchy, macos, or generic/linux-unknown
  #
  # DISTRO is intended for higher-level branching (which scripts to run),
  # not for fine-grained version logic.
  #
  # Omarchy note:
  #   Omarchy is treated as its own distro ID, even if it is layered on top
  #   of another base distro. This allows per-Omarchy tweaks if needed.
  #
  if [ "${PLATFORM:-}" = "macos" ]; then
    DISTRO="macos"
    return 0
  fi

  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "$ID" in
    ubuntu | debian)
      DISTRO="$ID"
      ;;
    arch | endeavouros | manjaro)
      DISTRO="arch"
      ;;
    proxmox)
      DISTRO="proxmox"
      ;;
    omarchy)
      DISTRO="omarchy"
      ;;
    *)
      DISTRO="$ID"
      warn "Unrecognised distro ID '$ID'; using DISTRO='$DISTRO'"
      ;;
    esac
  else
    DISTRO="linux-unknown"
    warn "No /etc/os-release found; using DISTRO='$DISTRO'"
  fi

  return 0
}

detect_pkg_manager() {
  # Sets PKG_MGR to one of: apt, pacman, brew, none.
  #
  # This is a coarse detection intended for basic package installs in
  # env-installer. Individual scripts can apply more specific behaviour
  # if needed.
  #
  # usage:
  #   detect_platform
  #   detect_pkg_manager
  #   ensure_packages git curl
  if [ "${PLATFORM:-}" = "macos" ]; then
    if available brew; then
      PKG_MGR="brew"
    else
      PKG_MGR="none"
    fi
    return 0
  fi

  if available apt-get; then
    PKG_MGR="apt"
  elif available pacman; then
    PKG_MGR="pacman"
  else
    PKG_MGR="none"
  fi

  return 0
}

# ---- device detection -------------------------------------------------------

_slugify_device_id() {
  # Normalise a string into lowercase kebab-case.
  # Example: "LENOVO ThinkPad X240" -> "lenovo-thinkpad-x240"
  #
  # Note: keep this POSIX-sh compatible.
  printf '%s' "${1:-}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

detect_device_id() {
  # Sets DEVICE_ID to a stable-ish identifier for the current machine.
  #
  # Priority:
  #   1) ENV_INSTALLER_DEVICE_ID (explicit override)
  #   2) Linux DMI info (/sys/devices/virtual/dmi/id/*)
  #   3) macOS Model Identifier (system_profiler)
  #   4) Fallback: "unknown"
  #
  # This is meant for *device-specific steps* (e.g. ThinkPad X240 tweaks).
  # It is not used for general platform/distro branching.

  if [ -n "${ENV_INSTALLER_DEVICE_ID:-}" ]; then
    DEVICE_ID="$(_slugify_device_id "$ENV_INSTALLER_DEVICE_ID")"
    return 0
  fi

  case "${PLATFORM:-}" in
    linux)
      # Best-effort: vendor + product name from DMI.
      if [ -r /sys/devices/virtual/dmi/id/product_name ]; then
        _pn="$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true)"
        _sv=""
        if [ -r /sys/devices/virtual/dmi/id/sys_vendor ]; then
          _sv="$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || true)"
        fi

        if [ -n "$_sv" ] && [ -n "$_pn" ]; then
          DEVICE_ID="$(_slugify_device_id "$_sv $_pn")"
          return 0
        fi
        if [ -n "$_pn" ]; then
          DEVICE_ID="$(_slugify_device_id "$_pn")"
          return 0
        fi
      fi

      DEVICE_ID="unknown"
      warn "Could not determine DEVICE_ID from DMI; using DEVICE_ID='$DEVICE_ID'"
      ;;
    macos)
      # Example: "Model Identifier: Macmini9,1"
      if available system_profiler; then
        _mi="$(
          system_profiler SPHardwareDataType 2>/dev/null \
            | awk -F': ' '/Model Identifier/ {print $2; exit}' \
            || true
        )"
        if [ -n "$_mi" ]; then
          DEVICE_ID="$(_slugify_device_id "$_mi")"
          return 0
        fi
      fi

      DEVICE_ID="unknown"
      warn "Could not determine DEVICE_ID on macOS; using DEVICE_ID='$DEVICE_ID'"
      ;;
    *)
      DEVICE_ID="unknown"
      warn "PLATFORM not set; using DEVICE_ID='$DEVICE_ID'"
      ;;
  esac

  return 0
}

require_device() {
  # Guard for device-specific steps.
  #
  # Usage:
  #   require_device "thinkpad-x240"
  #
  # Behaviour:
  #   - If DEVICE_ID matches: continue
  #   - Otherwise: log and exit 0 (soft skip)
  #
  # Rationale:
  #   Device-specific steps should not error on other machines.
  _required="${1:-}"
  [ -n "$_required" ] || die "require_device requires a device id argument"

  if [ "${DEVICE_ID:-unknown}" != "$_required" ]; then
    log "Skipping: requires DEVICE_ID='$_required' (current='${DEVICE_ID:-unknown}')."
    exit 0
  fi
}

# ---- privilege escalation ---------------------------------------------------

init_sudo() {
  # Initialises SUDO variable for commands that need root.
  #
  # If already root, SUDO is empty and commands run directly.
  # Otherwise, SUDO is set to the first available "sudo-like" tool.
  #
  # usage:
  #   init_sudo
  #   as_root mkdir -p /some/system/path
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
  else
    SUDO="$(first_of sudo doas run0 pkexec sudo-rs || true)"
    if [ -z "$SUDO" ]; then
      warn "No sudo-like command found; operations requiring root will fail."
    fi
  fi
}

as_root() {
  # Run a command as root, using SUDO if necessary.
  # If SUDO is empty or not set, runs the command directly.
  #
  # usage:
  #   as_root apt-get update -y
  if [ "$(id -u)" -eq 0 ] || [ -z "${SUDO:-}" ]; then
    run "$@"
  else
    run "$SUDO" "$@"
  fi
}

# ---- package install abstraction -------------------------------------------

ensure_packages() {
  # Install the given packages using the detected package manager.
  # Safe to call multiple times; package managers handle idempotency.
  #
  # Returns:
  #   0 - attempted install via supported PKG_MGR (or no args)
  #   1 - cannot install (PKG_MGR none/unknown)
  [ "$#" -gt 0 ] || return 0

  case "${PKG_MGR:-none}" in
    apt)
      as_root apt-get update -y
      as_root apt-get install -y "$@"
      ;;
    pacman)
      as_root pacman -Sy --needed --noconfirm "$@"
      ;;
    brew)
      run brew install "$@"
      ;;
    none)
      warn "No supported package manager detected; cannot install: $*"
      return 1
      ;;
    *)
      warn "Unknown PKG_MGR='${PKG_MGR:-}'; cannot install: $*"
      return 1
      ;;
  esac

  return 0
}
