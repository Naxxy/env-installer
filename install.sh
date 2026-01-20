#!/usr/bin/env sh
# env-installer: main entrypoint
#
# Responsibilities of this script:
#   - Detect basic environment (platform, distro, arch, device id, package manager).
#   - Initialise a per-run LOGFILE and write a header for this run.
#   - Discover "step" scripts under steps/ (including scoped subdirs).
#   - Run all steps (in order) or only named steps, based on CLI args.
#
# Step discovery supports the following (when present):
#   steps/*.sh
#   steps/<platform>/*.sh
#   steps/<platform>/<distro>/*.sh
#   steps/<platform>/arch/<arch>/*.sh
#   steps/devices/<device-id>/*.sh
#
# Precedence (last wins) when two scripts define the same step name:
#   generic < platform < distro < arch < device
#
# Real work happens in step scripts, which can:
#   - Assume LOGFILE exists and is writable (installer sets it up)
#   - Use add_title / add_comments for their own logging
#
# CLI defaults:
#   - No flags (and no args) means: run ALL steps
#   - Use --steps to run only selected steps (in the order provided)

set -eu

# --------------------------------------------------------------------
# Repository root resolution
# --------------------------------------------------------------------
# ROOT_DIR is the absolute path to the directory containing this script.
# This lets us run the installer from *any* working directory and still
# reliably locate lib/common.sh and steps/.
ROOT_DIR="$(
  CDPATH= cd -- "$(dirname -- "$0")" && pwd
)"

STEPS_DIR="$ROOT_DIR/steps"

# --------------------------------------------------------------------
# Load shared helpers
# --------------------------------------------------------------------
# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"

# --------------------------------------------------------------------
# Logging setup
# --------------------------------------------------------------------
# Each run gets its own log file named with a timestamp.
#
# Directory selection:
#   - If ENV_INSTALLER_LOG_DIR is set: use that.
#   - Else if XDG_STATE_HOME is set:
#       $XDG_STATE_HOME/env-installer/
#   - Else:
#       $HOME/.local/state/env-installer/
#
# Filename pattern:
#   installer-YYYYMMDDThhmmss±zzzz.log
#
# Example:
#   installer-20260112T031522+0700.log
#
# This makes it easy to:
#   - Sort logs by filename to get chronological order
#   - Delete old logs by age / pattern

init_logfile() {
  # Decide on log directory (ENV_INSTALLER_LOG_DIR overrides everything).
  #
  # Preference order:
  #   1) ENV_INSTALLER_LOG_DIR (explicit override)
  #   2) XDG_STATE_HOME (preferred on modern Linux)
  #   3) ~/.local/state (reasonable fallback across Linux/macOS)
  if [ -n "${ENV_INSTALLER_LOG_DIR:-}" ]; then
    LOG_DIR="$ENV_INSTALLER_LOG_DIR"
  elif [ -n "${XDG_STATE_HOME:-}" ]; then
    LOG_DIR="$XDG_STATE_HOME/env-installer"
  else
    LOG_DIR="$HOME/.local/state/env-installer"
  fi

  mkdir -p "$LOG_DIR"

  # RUN_ID is filename-friendly and sorts by time. Include timezone offset.
  # Example: 20260120T123456+0800
  RUN_STARTED_AT="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  RUN_ID="$(date '+%Y%m%dT%H%M%S%z')"

  LOGFILE="$LOG_DIR/installer-$RUN_ID.log"

  # Create/truncate, then require it exists.
  : >"$LOGFILE"

  # Sanity check: this should never fail now.
  require_logfile

  # Add a run header so each logfile is self-describing.
  add_title "env-installer run ($RUN_STARTED_AT)"

  # Free-form details: environment snapshot before any steps run.
  add_comments <<EOF
Run started at: $RUN_STARTED_AT

Platform:  $PLATFORM
Distro:    $DISTRO
Arch:      $ARCH
Device:    ${DEVICE_ID:-unknown}
PKG_MGR:   ${PKG_MGR:-none}

Steps directory: $STEPS_DIR
Log directory:   $LOG_DIR
Log file:        $LOGFILE
EOF
}

# --------------------------------------------------------------------
# CLI help / usage
# --------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 [--list] [--steps step1 step2 ...] [--all]

Options:
  --list              List available steps and exit.
  --steps <step...>   Run only the listed steps, in the order provided.
  --all               Run all steps (in numeric order based on filename prefix).
  -h, --help          Show this help.

Defaults:
  - If no flags are provided, ALL steps are run.

Examples:
  # Run all steps (default)
  $0

  # List available steps
  $0 --list

  # Run only selected steps (in the order given)
  $0 --steps env-info dev-tools

Notes:
  - Step names come from filenames like: 010-env-info.sh -> "env-info"
  - Scoped directories can override generic steps:
      steps/ < steps/\$PLATFORM < steps/\$PLATFORM/\$DISTRO < steps/\$PLATFORM/arch/\$ARCH < steps/devices/\$DEVICE_ID
EOF
}

# --------------------------------------------------------------------
# Step discovery
# --------------------------------------------------------------------

# find_step_files
#   Emits the *filenames* of all step scripts, one per line, sorted
#   lexicographically. We rely on numeric prefixes (e.g. "10-") to
#   establish ordering.
#
#   Example output:
#     10-env-info.sh
#     20-dev-tools.sh
find_step_files() {
  # We only care about files directly under $STEPS_DIR that end with .sh.
  # We strip the path so downstream functions see a simple "NN-name.sh".
  if [ ! -d "$STEPS_DIR" ]; then
    die "Steps directory not found: $STEPS_DIR"
  fi

  find "$STEPS_DIR" -maxdepth 1 -type f -name '*.sh' |
    sed 's|.*/||' |
    sort
}

# filename_to_step
#   Converts a filename like "10-env-info.sh" into the logical step name
#   "env-info". The numeric prefix and ".sh" extension are removed.
#
#   This is what the user passes on the CLI.
filename_to_step() {
  fname="$1"
  fname="${fname%.sh}" # strip .sh
  echo "${fname#*-}"   # strip leading "NN-"
}

# list_steps
#   Prints all known steps in a tabular form: "<step-name>\t<filename>".
#   Used for --list, and also useful for debugging.
list_steps() {
  for f in $(find_step_files); do
    step="$(filename_to_step "$f")"
    printf '%s\t%s\n' "$step" "$f"
  done
}

# --------------------------------------------------------------------
# Step execution
# --------------------------------------------------------------------

# run_step <step-name>
#   Locates the corresponding step script (NN-<step-name>.sh) and executes it.
#   If no matching step is found, the script fails with a clear error.
#
#   The following environment variables are exported to the step:
#     STEP_NAME  - the logical step name (e.g. "env-info")
#     PLATFORM   - linux / macos
#     DISTRO     - ubuntu / debian / arch / proxmox / macos / ...
#     ARCH       - x86_64 / aarch64 / ...
#     PKG_MGR    - apt / pacman / brew / none
#     SUDO       - sudo-like command or empty
#     LOGFILE    - path to the per-run installer log file
#
#   Each step script can also call require_logfile / add_title / add_comments
#   to add its own header and explanation into the shared log.
run_step() {
  step="$1"

  # Look for a matching filename in the discovered steps.
  for f in $(find_step_files); do
    name="$(filename_to_step "$f")"
    if [ "$name" = "$step" ]; then
      log "=== Running step: $step ($f) ==="
      STEP_NAME="$step" \
        PLATFORM="$PLATFORM" DISTRO="$DISTRO" ARCH="$ARCH" \
        PKG_MGR="$PKG_MGR" SUDO="${SUDO:-}" LOGFILE="$LOGFILE" \
        sh "$STEPS_DIR/$f"
      log "=== Finished step: $step ==="
      return 0
    fi
  done

  # If we got here, no matching filename existed.
  die "Unknown step: $step"
}

# --------------------------------------------------------------------
# Main flow
# --------------------------------------------------------------------
main() {
  # 1. Detect environment once and reuse the results for all steps.
  #    This keeps behaviour consistent across the entire run.
  detect_platform
  detect_arch
  detect_distro
  detect_pkg_manager
  detect_device_id
  init_sudo

  # Emit an initial terminal line (also goes to LOGFILE after init_logfile).
  log "Platform: $PLATFORM, Distro: $DISTRO, Arch: $ARCH, Device: ${DEVICE_ID:-unknown}, PKG_MGR: ${PKG_MGR:-none}"

  # 2. Initialise the per-run LOGFILE and write a run header.
  #    After this, steps can safely assume LOGFILE exists and is writable.
  init_logfile
  log "Logging to: $LOGFILE"

  RUN_ALL=false
  STEPS=""

  # 3. Parse CLI arguments.
  #
  #    Supported forms:
  #      $0 --all
  #      $0 --list
  #      $0 step1 step2 ...
  #
  #    Rule: if neither --all nor explicit steps are provided, we treat it
  #    as "--all" by default (see check after parsing).
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --all)
      RUN_ALL=true
      ;;
    --list)
      list_steps
      exit 0
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      # Any non-flag argument is treated as a step name.
      # We preserve order so user-specified sequence is respected.
      STEPS="$STEPS $1"
      ;;
    esac
    shift
  done

  # 4. Decide what to run.
  #
  #    If the user did not explicitly request --all and also did not
  #    specify any steps, default to running all steps.
  if [ "$RUN_ALL" = false ] && [ -z "$STEPS" ]; then
    RUN_ALL=true
  fi

  # 5. Execute either:
  #      - all steps (in filename order), or
  #      - only the named steps (in the order provided on the CLI).
  if [ "$RUN_ALL" = true ]; then
    for f in $(find_step_files); do
      step="$(filename_to_step "$f")"
      run_step "$step"
    done
  else
    # Run only the selected steps, in the order given.
    # STEPS is a space-separated list of names.
    for step in $STEPS; do
      run_step "$step"
    done
  fi

  log "All requested steps completed."
}

main "$@"
