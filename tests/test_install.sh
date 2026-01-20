
#!/usr/bin/env sh
set -eu

# Root of the repo: tests/.. → project root containing install.sh and lib/common.sh
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# --------------------------------------------------------------------
# Pretty test output helpers (same style as test_common.sh)
# --------------------------------------------------------------------

t_header() {
  printf '────────────────────────────────────────────────────────\n'
  printf ' TEST: %s\n' "$1"
  printf '────────────────────────────────────────────────────────\n'
}

t_info() {
  printf '[INFO] %s\n' "$1"
}

t_block() {
  label="$1"
  content="$2"
  if [ -z "$content" ]; then
    printf '[INFO] %s: <none>\n' "$label"
    return
  fi
  printf '[INFO] %s:\n' "$label"
  printf '%s\n' "$content" | while IFS= read -r line; do
    printf '       %s\n' "$line"
  done
}

# --------------------------------------------------------------------
# Tiny assertion helpers
# --------------------------------------------------------------------

fail() {
  printf '[TEST ERR] %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected="$1"
  actual="$2"
  if [ "$expected" != "$actual" ]; then
    printf '[TEST ERR] assert_eq failed:\n' >&2
    printf '  expected:\n%s\n' "$expected" >&2
    printf '  actual:\n%s\n' "$actual" >&2
    exit 1
  fi
}

assert_in() {
  needle="$1"
  haystack="$2"
  case "$haystack" in
    *"$needle"*) : ;;
    *)
      printf '[TEST ERR] assert_in failed: "%s" not found in:\n%s\n' "$needle" "$haystack" >&2
      exit 1
      ;;
  esac
}

# --------------------------------------------------------------------
# Fixture helpers
# --------------------------------------------------------------------
# Each test gets its own temporary "mini repo" with:
#   FIX_DIR/install.sh
#   FIX_DIR/lib/common.sh
#   FIX_DIR/steps/.../*.sh
#   FIX_DIR/logs/ (for ENV_INSTALLER_LOG_DIR)

setup_fixture() {
  FIX_DIR="$(mktemp -d)"
  LOG_DIR="$FIX_DIR/logs"

  mkdir -p "$FIX_DIR/lib" "$FIX_DIR/steps" "$LOG_DIR"

  # Copy the real scripts into the fixture so relative paths still work
  cp "$ROOT_DIR/install.sh" "$FIX_DIR/install.sh"
  cp "$ROOT_DIR/lib/common.sh" "$FIX_DIR/lib/common.sh"

  chmod +x "$FIX_DIR/install.sh"
}

cleanup_fixture() {
  rm -rf "${FIX_DIR:-}" 2>/dev/null || true
}

# Helper to run the installer in the fixture.
#
# Notes:
# - We always set ENV_INSTALLER_LOG_DIR so logs land inside the fixture.
# - We also set BOTH ENV_INSTALLER_DEVICE_ID and ENV_INSTALLER_DEVICE as overrides,
#   to match whichever env-var name detect_device_id() expects.
run_installer() {
  (
    cd "$FIX_DIR"
    ENV_INSTALLER_LOG_DIR="$LOG_DIR" \
    ENV_INSTALLER_DEVICE_ID="${ENV_INSTALLER_DEVICE_ID:-}" \
    ENV_INSTALLER_DEVICE="${ENV_INSTALLER_DEVICE:-}" \
    sh "$FIX_DIR/install.sh" "$@"
  )
}

# Create a dummy step directly under steps/
create_step() {
  # create_step <numeric-prefix> <name> <body>
  num="$1"
  name="$2"
  body="$3"

  cat >"$FIX_DIR/steps/${num}-${name}.sh" <<EOF
#!/usr/bin/env sh
set -eu
$body
EOF
  chmod +x "$FIX_DIR/steps/${num}-${name}.sh"
}

# Create a dummy scoped step under steps/<relative-dir>/
create_scoped_step() {
  # create_scoped_step <relative-dir> <numeric-prefix> <name> <body>
  rel_dir="$1"
  num="$2"
  name="$3"
  body="$4"

  mkdir -p "$FIX_DIR/steps/$rel_dir"

  cat >"$FIX_DIR/steps/$rel_dir/${num}-${name}.sh" <<EOF
#!/usr/bin/env sh
set -eu
$body
EOF
  chmod +x "$FIX_DIR/steps/$rel_dir/${num}-${name}.sh"
}

# --------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------

test_list_steps_outputs_expected() {
  t_header "test_list_steps_outputs_expected"
  setup_fixture

  create_step "10" "env-info" 'echo "STEP:env-info"'
  create_step "20" "dev-tools" 'echo "STEP:dev-tools"'

  # --list should print "<step>\t<relpath>" and NOT run the steps
  out="$(run_installer --list || true)"
  t_block "raw --list output" "$out"

  # Filter out the [INFO] log lines; keep only the step list lines
  list_lines="$(printf '%s\n' "$out" | grep -v '^\[INFO\]' || true)"
  t_block "parsed step list" "$list_lines"

  # Expected two lines, with real tabs between step name and relative path
  expected="$(printf 'env-info\t10-env-info.sh\ndev-tools\t20-dev-tools.sh')"
  assert_eq "$expected" "$list_lines"

  # Ensure --list did NOT execute the steps (no STEP:... lines anywhere)
  steps_run="$(printf '%s\n' "$out" | grep '^STEP:' || true)"
  [ -z "$steps_run" ] || fail "--list should not execute steps, but saw:\n$steps_run"

  cleanup_fixture
  printf '\n'
}

test_main_default_runs_all_steps_in_order() {
  t_header "test_main_default_runs_all_steps_in_order"
  setup_fixture

  create_step "10" "env-info" 'echo "STEP:env-info"'
  create_step "20" "dev-tools" 'echo "STEP:dev-tools"'

  out="$(run_installer || true)"

  steps_run="$(printf '%s\n' "$out" | grep '^STEP:' || true)"
  t_block "STEP lines" "$steps_run"

  expected="STEP:env-info
STEP:dev-tools"
  assert_eq "$expected" "$steps_run"

  cleanup_fixture
  printf '\n'
}

test_steps_flag_runs_only_requested_steps_in_given_order() {
  t_header "test_steps_flag_runs_only_requested_steps_in_given_order"
  setup_fixture

  create_step "10" "env-info" 'echo "STEP:env-info"'
  create_step "20" "dev-tools" 'echo "STEP:dev-tools"'
  create_step "30" "desktop" 'echo "STEP:desktop"'

  # Request steps in non-numeric order: dev-tools then env-info
  out="$(run_installer --steps dev-tools env-info || true)"

  steps_run="$(printf '%s\n' "$out" | grep '^STEP:' || true)"
  t_block "STEP lines" "$steps_run"

  expected="STEP:dev-tools
STEP:env-info"
  assert_eq "$expected" "$steps_run"

  cleanup_fixture
  printf '\n'
}

test_positional_args_are_rejected() {
  t_header "test_positional_args_are_rejected"
  setup_fixture

  create_step "10" "env-info" 'echo "STEP:env-info"'

  # Non-flag args are no longer accepted; steps must be provided via --steps.
  if out="$(run_installer env-info 2>&1)"; then
    cleanup_fixture
    fail "Installer should fail when given positional args (expected a hard error)"
  fi

  t_block "stderr for positional arg" "$out"
  assert_in "Unknown argument:" "$out"
  assert_in "use --steps" "$out"

  cleanup_fixture
  printf '\n'
}

test_unknown_step_under_steps_flag_causes_failure() {
  t_header "test_unknown_step_under_steps_flag_causes_failure"
  setup_fixture

  create_step "10" "env-info" 'echo "STEP:env-info"'

  # With --steps, an unknown step should fail with "Unknown step: ..."
  if out="$(run_installer --steps does-not-exist 2>&1)"; then
    cleanup_fixture
    fail "Installer should fail for unknown step under --steps"
  fi

  t_block "stderr for unknown step" "$out"
  assert_in "Unknown step: does-not-exist" "$out"

  cleanup_fixture
  printf '\n'
}

test_logfile_created_and_header_written() {
  t_header "test_logfile_created_and_header_written"
  setup_fixture

  # Minimal step to ensure main completes cleanly
  create_step "10" "noop" 'echo "STEP:noop"'

  run_installer >/dev/null 2>&1 || fail "Installer run failed unexpectedly"

  # Expect at least one installer-*.log in LOG_DIR (one per run)
  log_file="$(ls "$LOG_DIR"/installer-*.log 2>/dev/null | sort | tail -n 1 || true)"
  if [ -z "$log_file" ]; then
    fail "Expected at least one log file matching: $LOG_DIR/installer-*.log"
  fi

  t_info "Using log file: $log_file"

  content="$(cat "$log_file")"
  t_block "log file content" "$content"

  # Basic sanity: header & environment snapshot
  assert_in "env-installer run (" "$content"
  assert_in "Platform:" "$content"
  assert_in "Distro:" "$content"
  assert_in "Arch:" "$content"
  assert_in "Device:" "$content"
  assert_in "PKG_MGR:" "$content"

  cleanup_fixture
  printf '\n'
}

test_device_scoped_step_overrides_generic() {
  t_header "test_device_scoped_step_overrides_generic"
  setup_fixture

  # Pretend we're on a specific device. We set both env vars to match whichever common.sh uses.
  ENV_INSTALLER_DEVICE_ID="thinkpad-x240"
  ENV_INSTALLER_DEVICE="thinkpad-x240"
  export ENV_INSTALLER_DEVICE_ID ENV_INSTALLER_DEVICE

  # Same logical step name in both places ("env-info"), device should override generic.
  create_step "10" "env-info" 'echo "STEP:generic-env-info"'
  create_scoped_step "devices/thinkpad-x240" "10" "env-info" 'echo "STEP:device-env-info"'

  out="$(run_installer || true)"

  steps_run="$(printf '%s\n' "$out" | grep '^STEP:' || true)"
  t_block "STEP lines" "$steps_run"

  # Should run only the overridden step output once (device version), and NOT the generic one.
  assert_in "STEP:device-env-info" "$steps_run"
  case "$steps_run" in
    *"STEP:generic-env-info"*)
      cleanup_fixture
      fail "Expected device-scoped step to override generic, but generic step output was present:\n$steps_run"
      ;;
    *)
      : ;;
  esac

  cleanup_fixture
  printf '\n'
}

# --------------------------------------------------------------------
# Test runner
# --------------------------------------------------------------------

main() {
  printf '────────────────────────────────────────────────────────\n'
  printf ' TEST RUNNER: install.sh tests\n'
  printf '────────────────────────────────────────────────────────\n\n'

  test_list_steps_outputs_expected
  test_main_default_runs_all_steps_in_order
  test_steps_flag_runs_only_requested_steps_in_given_order
  test_positional_args_are_rejected
  test_unknown_step_under_steps_flag_causes_failure
  test_logfile_created_and_header_written
  test_device_scoped_step_overrides_generic

  printf '────────────────────────────────────────────────────────\n'
  printf ' ALL install.sh TESTS PASSED\n'
  printf '────────────────────────────────────────────────────────\n'
}

main "$@"
