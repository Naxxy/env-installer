#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"

# ---------------------------
# Test output helpers
# ---------------------------

t_header() {
  printf '────────────────────────────────────────────────────────\n'
  printf ' TEST: %s\n' "$1"
  printf '────────────────────────────────────────────────────────\n'
}

t_kv() {
  # Key/value on one line
  printf '[INFO] %-14s %s\n' "$1" "$2"
}

t_block() {
  # Label + multi-line block, indented
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

t_sep() {
  printf '\n'
}

# ---------------------------
# Tiny assertion helpers
# ---------------------------

fail() {
  printf '[TEST ERR] %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected="$1"
  actual="$2"
  if [ "$expected" != "$actual" ]; then
    printf '[TEST ERR] assert_eq failed:\n' >&2
    printf '         expected: %s\n' "$expected" >&2
    printf '         actual:   %s\n' "$actual" >&2
    exit 1
  fi
}

assert_ne() {
  not_expected="$1"
  actual="$2"
  if [ "$not_expected" = "$actual" ]; then
    printf '[TEST ERR] assert_ne failed:\n' >&2
    printf '         not_expected: %s\n' "$not_expected" >&2
    printf '         actual:       %s\n' "$actual" >&2
    exit 1
  fi
}

assert_in() {
  needle="$1"
  haystack="$2"
  case "$haystack" in
    *"$needle"*) : ;;
    *)
      printf '[TEST ERR] assert_in failed:\n' >&2
      printf '         needle:   %s\n' "$needle" >&2
      printf '         haystack: %s\n' "$haystack" >&2
      exit 1
      ;;
  esac
}

assert_exit_code() {
  expected="$1"
  actual="$2"
  if [ "$expected" -ne "$actual" ]; then
    printf '[TEST ERR] assert_exit_code failed: expected=%s actual=%s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

# ---------------------------
# Tests
# ---------------------------

test_log_and_warn_do_not_crash() {
  t_header "test_log_and_warn_do_not_crash"

  out_log="$(log "hello world" 2>/dev/null || true)"
  out_warn="$(warn "oops" 2>&1 1>/dev/null || true)"

  t_block "log output" "$out_log"
  t_block "warn output" "$out_warn"

  assert_in "INFO" "$out_log"
  assert_in "hello world" "$out_log"

  assert_in "WARN" "$out_warn"
  assert_in "oops" "$out_warn"
  t_sep
}

test_die_exits_non_zero() {
  t_header "test_die_exits_non_zero"

  if out="$(sh -c ". \"$ROOT_DIR/lib/common.sh\"; die \"boom\"" 2>&1)"; then
    fail "die did not exit non-zero"
  fi

  t_block "die output" "$out"

  assert_in "ERR" "$out"
  assert_in "boom" "$out"
  t_sep
}

test_log_warn_die_also_write_to_logfile_when_set() {
  t_header "test_log_warn_die_also_write_to_logfile_when_set"

  tmp="$(mktemp)"
  : >"$tmp"

  out_log="$(LOGFILE="$tmp" log "hello file" 2>/dev/null || true)"
  t_block "log stdout" "$out_log"

  file_after_log="$(cat "$tmp")"
  t_block "logfile after log" "$file_after_log"

  assert_in "INFO" "$out_log"
  assert_in "hello file" "$out_log"
  assert_in "INFO" "$file_after_log"
  assert_in "hello file" "$file_after_log"

  out_warn="$(LOGFILE="$tmp" warn "warn file" 2>&1 1>/dev/null || true)"
  t_block "warn stderr" "$out_warn"

  file_after_warn="$(cat "$tmp")"
  t_block "logfile after warn" "$file_after_warn"

  assert_in "WARN" "$out_warn"
  assert_in "warn file" "$out_warn"
  assert_in "WARN" "$file_after_warn"
  assert_in "warn file" "$file_after_warn"

  if out_die="$(LOGFILE="$tmp" sh -c ". \"$ROOT_DIR/lib/common.sh\"; LOGFILE=\"$tmp\"; die \"die file\"" 2>&1)"; then
    fail "die did not exit non-zero"
  fi
  t_block "die stderr" "$out_die"

  file_after_die="$(cat "$tmp")"
  t_block "logfile after die" "$file_after_die"

  assert_in "ERR" "$out_die"
  assert_in "die file" "$out_die"
  assert_in "ERR" "$file_after_die"
  assert_in "die file" "$file_after_die"

  rm -f "$tmp"
  t_sep
}

test_require_logfile_success_and_failure() {
  t_header "test_require_logfile_success_and_failure"

  tmp="$(mktemp)"
  LOGFILE="$tmp" require_logfile
  t_kv "success" "LOGFILE=$tmp"
  rm -f "$tmp"

  if out="$(sh -c ". \"$ROOT_DIR/lib/common.sh\"; unset LOGFILE; require_logfile" 2>&1)"; then
    fail "require_logfile should fail when LOGFILE is unset"
  fi
  t_block "unset LOGFILE" "$out"
  assert_in "LOGFILE is not set" "$out"

  if out2="$(sh -c ". \"$ROOT_DIR/lib/common.sh\"; LOGFILE=/tmp/this-should-not-exist-$$; require_logfile" 2>&1)"; then
    fail "require_logfile should fail when LOGFILE does not exist"
  fi
  t_block "missing file" "$out2"
  assert_in "does not exist" "$out2"
  t_sep
}

test_add_title_with_explicit_title() {
  t_header "test_add_title_with_explicit_title"

  tmp="$(mktemp)"
  LOGFILE="$tmp"
  : >"$LOGFILE"

  add_title "My Title"

  content="$(cat "$LOGFILE")"
  t_block "title block" "$content"

  assert_in "My Title" "$content"
  assert_in "===================================" "$content"

  rm -f "$tmp"
  t_sep
}

test_add_comments_appends_stdin() {
  t_header "test_add_comments_appends_stdin"

  tmp="$(mktemp)"
  LOGFILE="$tmp"
  : >"$LOGFILE"

  add_title "Header"
  printf 'Line one\nLine two\n' | add_comments

  content="$(cat "$LOGFILE")"
  t_block "logfile content" "$content"

  assert_in "Header" "$content"
  assert_in "Line one" "$content"
  assert_in "Line two" "$content"

  rm -f "$tmp"
  t_sep
}

test_available_and_first_of() {
  t_header "test_available_and_first_of"

  if ! available sh; then
    fail "expected 'sh' to be available"
  fi

  if available "this-command-should-not-exist-12345"; then
    fail "available() returned success for nonexistent command"
  fi

  first="$(first_of this-command-should-not-exist-12345 sh)"
  t_kv "first_of" "$first"
  assert_eq "sh" "$first"
  t_sep
}

test_run_executes_command() {
  t_header "test_run_executes_command"

  out="$(run printf 'hello-from-run')"
  t_kv "stdout" "$out"
  assert_eq "hello-from-run" "$out"
  t_sep
}

test_detect_platform_and_arch() {
  t_header "test_detect_platform_and_arch"

  detect_platform
  detect_arch

  t_kv "PLATFORM" "$PLATFORM"
  t_kv "ARCH" "$ARCH"

  case "$PLATFORM" in
    linux|macos) : ;;
    *) fail "Unexpected PLATFORM='$PLATFORM' (expected linux or macos)" ;;
  esac

  [ -n "$ARCH" ] || fail "ARCH should not be empty"
  t_sep
}

test_detect_distro() {
  t_header "test_detect_distro"

  detect_platform
  detect_distro

  t_kv "PLATFORM" "$PLATFORM"
  t_kv "DISTRO" "$DISTRO"

  [ -n "$DISTRO" ] || fail "DISTRO should not be empty"
  t_sep
}

test_detect_pkg_manager() {
  t_header "test_detect_pkg_manager"

  detect_platform
  detect_distro
  detect_pkg_manager

  t_kv "PLATFORM" "$PLATFORM"
  t_kv "DISTRO" "$DISTRO"
  t_kv "PKG_MGR" "${PKG_MGR:-<unset>}"

  case "${PKG_MGR:-none}" in
    apt|pacman|brew|none) : ;;
    *) fail "Unexpected PKG_MGR='$PKG_MGR' (expected apt/pacman/brew/none)" ;;
  esac
  t_sep
}

# ---------------------------
# New: device-id helpers
# ---------------------------

test_slugify_device_id_normalises_string() {
  t_header "test_slugify_device_id_normalises_string"

  in="LENOVO ThinkPad X240"
  out="$(_slugify_device_id "$in")"

  t_kv "input" "$in"
  t_kv "output" "$out"

  assert_eq "lenovo-thinkpad-x240" "$out"
  t_sep
}

test_detect_device_id_uses_override_when_set() {
  t_header "test_detect_device_id_uses_override_when_set"

  # Make sure PLATFORM is set (detect_device_id branches on it)
  detect_platform

  ENV_INSTALLER_DEVICE_ID="ThinkPad X240" detect_device_id

  t_kv "PLATFORM" "$PLATFORM"
  t_kv "DEVICE_ID" "$DEVICE_ID"

  assert_eq "thinkpad-x240" "$DEVICE_ID"
  t_sep
}

test_require_device_skips_when_not_matching() {
  t_header "test_require_device_skips_when_not_matching"

  # Run in a subprocess so exit 0 doesn't end the test runner.
  out=""
  code=0
  out="$(sh -c ". \"$ROOT_DIR/lib/common.sh\"; DEVICE_ID=some-other-device; require_device thinkpad-x240; echo SHOULD_NOT_PRINT" 2>&1)" || code=$?

  t_kv "exit_code" "$code"
  t_block "output" "$out"

  # require_device is a soft-skip: should exit 0, and should not print the sentinel.
  assert_exit_code 0 "$code"
  assert_in "Skipping: requires DEVICE_ID='thinkpad-x240'" "$out"
  case "$out" in
    *"SHOULD_NOT_PRINT"*) fail "require_device did not exit early on mismatch" ;;
    *) : ;;
  esac
  t_sep
}

test_require_device_allows_when_matching() {
  t_header "test_require_device_allows_when_matching"

  out=""
  code=0
  out="$(sh -c ". \"$ROOT_DIR/lib/common.sh\"; DEVICE_ID=thinkpad-x240; require_device thinkpad-x240; echo OK_AFTER_GUARD" 2>&1)" || code=$?

  t_kv "exit_code" "$code"
  t_block "output" "$out"

  assert_exit_code 0 "$code"
  assert_in "OK_AFTER_GUARD" "$out"
  t_sep
}

test_init_sudo_sets_var_or_warns() {
  t_header "test_init_sudo_sets_var_or_warns"

  init_sudo

  t_kv "id -u" "$(id -u)"
  t_kv "SUDO" "${SUDO:-<unset>}"

  : "${SUDO:-}" # ensure variable is defined
  t_sep
}

test_as_root_uses_run_when_root_or_no_sudo() {
  t_header "test_as_root_uses_run_when_root_or_no_sudo"

  CALLS=""
  run() { CALLS="$CALLS|$*"; }

  unset SUDO || true
  as_root echo "hello-as-root"

  pretty="${CALLS#|}"
  t_block "CALLS" "$pretty"
  assert_in "echo hello-as-root" "$pretty"
  t_sep
}

test_as_root_uses_sudo_when_set() {
  t_header "test_as_root_uses_sudo_when_set"

  CALLS=""
  run() { CALLS="$CALLS|$*"; }

  SUDO="fake-sudo"
  as_root echo "hello-via-sudo"

  pretty="${CALLS#|}"
  t_block "CALLS" "$pretty"

  if [ "$(id -u)" -eq 0 ]; then
    assert_in "echo hello-via-sudo" "$pretty"
  else
    assert_in "fake-sudo echo hello-via-sudo" "$pretty"
  fi
  t_sep
}

test_ensure_packages_with_apt_mocked() {
  t_header "test_ensure_packages_with_apt_mocked"

  PKG_MGR="apt"
  CALLS=""

  run() { CALLS="$CALLS|$*"; }

  SUDO=""
  as_root() { CALLS="$CALLS|$*"; }

  ensure_packages git curl

  pretty="${CALLS#|}"
  t_block "CALLS" "$(printf '%s\n' "$pretty" | tr '|' '\n')"

  assert_in "apt-get update -y" "$pretty"
  assert_in "apt-get install -y git curl" "$pretty"
  t_sep
}

test_ensure_packages_with_pacman_mocked() {
  t_header "test_ensure_packages_with_pacman_mocked"

  PKG_MGR="pacman"
  CALLS=""

  run() { CALLS="$CALLS|$*"; }

  SUDO=""
  as_root() { CALLS="$CALLS|$*"; }

  ensure_packages git curl

  pretty="${CALLS#|}"
  t_block "CALLS" "$(printf '%s\n' "$pretty" | tr '|' '\n')"

  assert_in "pacman -Sy --needed --noconfirm git curl" "$pretty"
  t_sep
}

test_ensure_packages_with_brew_mocked() {
  t_header "test_ensure_packages_with_brew_mocked"

  PKG_MGR="brew"
  CALLS=""

  run() { CALLS="$CALLS|$*"; }

  ensure_packages git curl

  pretty="${CALLS#|}"
  t_block "CALLS" "$(printf '%s\n' "$pretty" | tr '|' '\n')"

  assert_in "brew install git curl" "$pretty"
  t_sep
}

test_ensure_packages_with_none_returns_non_zero() {
  t_header "test_ensure_packages_with_none_returns_non_zero"

  PKG_MGR="none"
  CALLS=""
  WARNINGS=""

  run() { CALLS="$CALLS|$*"; }
  warn() { WARNINGS="$WARNINGS|$*"; }

  if ensure_packages foo; then
    fail "ensure_packages should return non-zero when PKG_MGR=none"
  fi

  calls_pretty="${CALLS#|}"
  warns_pretty="${WARNINGS#|}"

  t_block "CALLS" "$calls_pretty"
  t_block "WARNINGS" "$warns_pretty"

  [ -z "$calls_pretty" ] || fail "run() should not be called when PKG_MGR=none"
  assert_in "No supported package manager detected" "$warns_pretty"
  t_sep
}

test_ensure_packages_with_unknown_returns_non_zero() {
  t_header "test_ensure_packages_with_unknown_returns_non_zero"

  PKG_MGR="totally-unknown"
  CALLS=""
  WARNINGS=""

  run() { CALLS="$CALLS|$*"; }
  warn() { WARNINGS="$WARNINGS|$*"; }

  if ensure_packages foo; then
    fail "ensure_packages should return non-zero when PKG_MGR is unknown"
  fi

  [ -z "${CALLS#|}" ] || fail "run() should not be called when PKG_MGR is unknown"
  assert_in "Unknown PKG_MGR" "${WARNINGS#|}"
  t_sep
}

# ---------------------------
# Test runner
# ---------------------------

main() {
  printf '────────────────────────────────────────────────────────\n'
  printf ' TEST RUNNER: common.sh tests\n'
  printf '────────────────────────────────────────────────────────\n\n'

  test_log_and_warn_do_not_crash
  test_die_exits_non_zero
  test_log_warn_die_also_write_to_logfile_when_set
  test_require_logfile_success_and_failure
  test_add_title_with_explicit_title
  test_add_comments_appends_stdin
  test_available_and_first_of
  test_run_executes_command
  test_detect_platform_and_arch
  test_detect_distro
  test_detect_pkg_manager

  # New device-id tests
  test_slugify_device_id_normalises_string
  test_detect_device_id_uses_override_when_set
  test_require_device_skips_when_not_matching
  test_require_device_allows_when_matching

  test_init_sudo_sets_var_or_warns
  test_as_root_uses_run_when_root_or_no_sudo
  test_as_root_uses_sudo_when_set
  test_ensure_packages_with_apt_mocked
  test_ensure_packages_with_pacman_mocked
  test_ensure_packages_with_brew_mocked
  test_ensure_packages_with_none_returns_non_zero
  test_ensure_packages_with_unknown_returns_non_zero

  printf '────────────────────────────────────────────────────────\n'
  printf ' ALL TESTS PASSED\n'
  printf '────────────────────────────────────────────────────────\n'
}

main "$@"
