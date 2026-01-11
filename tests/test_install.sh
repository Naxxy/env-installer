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
#   FIX_DIR/steps/*.sh
#   FIX_DIR/logs/ (for ENV_INSTALLER_LOG_DIR)

setup_fixture() {
  FIX_DIR="$(mktemp -d)"
  LOG_DIR="$FIX_DIR/logs"

  mkdir -p "$FIX_DIR/lib" "$FIX_DIR/steps" "$LOG_DIR"

  # Copy the real scripts into the fixture so relative paths still work
  cp "$ROOT_DIR/install.sh" "$FIX_DIR/install.sh"
  cp "$ROOT_DIR/lib/common.sh" "$FIX_DIR/lib/common.sh"
}

cleanup_fixture() {
  rm -rf "${FIX_DIR:-}" 2>/dev/null || true
}

# Helper to run the installer in the fixture
run_installer() {
  (
    cd "$FIX_DIR"
    ENV_INSTALLER_LOG_DIR="$LOG_DIR" sh "$FIX_DIR/install.sh" "$@"
  )
}

# Create some dummy steps in the fixture
create_step() {
  # create_step <numeric-prefix> <name> <body>
  num="$1"
  name="$2"
  body="$3"

  cat >"$FIX_DIR/steps/${num}-${name}.sh" <<EOF
#!/usr/bin/env sh
$body
EOF
  chmod +x "$FIX_DIR/steps/${num}-${name}.sh"
}

# --------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------

test_list_steps_outputs_expected() {
  t_header "test_list_steps_outputs_expected"
  setup_fixture

  create_step "10" "env-info" 'echo "STEP:env-info"'
  create_step "20" "dev-tools" 'echo "STEP:dev-tools"'

  # --list should print "<step>\t<filename>" and NOT run the steps
  out="$(run_installer --list || true)"

  t_block "raw --list output" "$out"

  # Filter out the [INFO] log lines; keep only the step list lines
  list_lines="$(printf '%s\n' "$out" | grep -v '^\[INFO\]' || true)"
  t_block "parsed step list" "$list_lines"

  # Expected two lines, with real tabs between step name and filename
  expected="$(printf 'env-info\t10-env-info.sh\ndev-tools\t20-dev-tools.sh')"
  assert_eq "$expected" "$list_lines"

  # Also ensure --list did NOT execute the steps (no STEP:... lines anywhere)
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

  # Extract just the STEP: lines
  steps_run="$(printf '%s\n' "$out" | grep '^STEP:' || true)"

  t_block "STEP lines" "$steps_run"

  expected="STEP:env-info
STEP:dev-tools"
  assert_eq "$expected" "$steps_run"

  cleanup_fixture
  printf '\n'
}

test_main_runs_only_requested_steps_in_given_order() {
  t_header "test_main_runs_only_requested_steps_in_given_order"
  setup_fixture

  create_step "10" "env-info" 'echo "STEP:env-info"'
  create_step "20" "dev-tools" 'echo "STEP:dev-tools"'
  create_step "30" "desktop" 'echo "STEP:desktop"'

  # Request steps in non-numeric order: dev-tools then env-info
  out="$(run_installer dev-tools env-info || true)"

  steps_run="$(printf '%s\n' "$out" | grep '^STEP:' || true)"
  t_block "STEP lines" "$steps_run"

  expected="STEP:dev-tools
STEP:env-info"
  assert_eq "$expected" "$steps_run"

  cleanup_fixture
  printf '\n'
}

test_unknown_step_causes_failure() {
  t_header "test_unknown_step_causes_failure"
  setup_fixture

  create_step "10" "env-info" 'echo "STEP:env-info"'

  # Capture stderr & exit code
  if out="$(run_installer does-not-exist 2>&1)"; then
    cleanup_fixture
    fail "Installer should fail for unknown step"
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

  # Run installer once
  run_installer >/dev/null 2>&1 || fail "Installer run failed unexpectedly"

  # We now expect at least one installer-*.log in LOG_DIR
  # Pick the newest one (lexicographically last)
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
  assert_in "PKG_MGR:" "$content"

  cleanup_fixture
  printf '\n'
}

test_all_flag_runs_all_steps_in_order() {
  t_header "test_all_flag_runs_all_steps_in_order"
  setup_fixture

  create_step "10" "first" 'echo "STEP:first"'
  create_step "20" "second" 'echo "STEP:second"'

  out="$(run_installer --all || true)"

  steps_run="$(printf '%s\n' "$out" | grep '^STEP:' || true)"
  t_block "STEP lines" "$steps_run"

  expected="STEP:first
STEP:second"
  assert_eq "$expected" "$steps_run"

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
  test_main_runs_only_requested_steps_in_given_order
  test_unknown_step_causes_failure
  test_logfile_created_and_header_written
  test_all_flag_runs_all_steps_in_order

  printf '────────────────────────────────────────────────────────\n'
  printf ' ALL install.sh TESTS PASSED\n'
  printf '────────────────────────────────────────────────────────\n'
}

main "$@"
