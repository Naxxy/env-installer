#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"

# ---------------------------
# Test output helpers
# ---------------------------

t_header() {
  # Pretty test section header
  printf '────────────────────────────────────────────────────────\n'
  printf ' TEST: %s\n' "$1"
  printf '────────────────────────────────────────────────────────\n'
}

t_info() {
  # Single-line info
  printf '[INFO] %s\n' "$1"
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
    printf '[TEST ERR] assert_eq failed: expected=%s actual=%s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

assert_in() {
  needle="$1"
  haystack="$2"
  case "$haystack" in
  *"$needle"*) : ;;
  *)
    printf '[TEST ERR] assert_in failed: "%s" not found in "%s"\n' "$needle" "$haystack" >&2
    exit 1
    ;;
  esac
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
  printf '\n'
}

test_die_exits_non_zero() {
  t_header "test_die_exits_non_zero"

  if out="$(sh -c ". \"$ROOT_DIR/lib/common.sh\"; die \"boom\"" 2>&1)"; then
    fail "die did not exit non-zero"
  fi

  t_block "die output" "$out"

  assert_in "ERR" "$out"
  assert_in "boom" "$out"
  printf '\n'
}

test_log_warn_die_also_write_to_logfile_when_set() {
  t_header "test_log_warn_die_also_write_to_logfile_when_set"

  tmp="$(mktemp)"
  : >"$tmp"

  # log -> stdout + logfile
  out_log="$(LOGFILE="$tmp" log "hello file" 2>/dev/null || true)"
  t_block "log stdout" "$out_log"

  file_after_log="$(cat "$tmp")"
  t_block "logfile after log" "$file_after_log"

  assert_in "INFO" "$out_log"
  assert_in "hello file" "$out_log"
  assert_in "INFO" "$file_after_log"
  assert_in "hello file" "$file_after_log"

  # warn -> stderr + logfile
  out_warn="$(LOGFILE="$tmp" warn "warn file" 2>&1 1>/dev/null || true)"
  t_block "warn stderr" "$out_warn"

  file_after_warn="$(cat "$tmp")"
  t_block "logfile after warn" "$file_after_warn"

  assert_in "WARN" "$out_warn"
  assert_in "warn file" "$out_warn"
  assert_in "WARN" "$file_after_warn"
  assert_in "warn file" "$file_after_warn"

  # die -> stderr + logfile + non-zero
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
  printf '\n'
}

test_require_logfile_success_and_failure() {
  t_header "test_require_logfile_success_and_failure"

  # Success case
  tmp="$(mktemp)"
  LOGFILE="$tmp" require_logfile
  t_info "LOGFILE success: $tmp"
  rm -f "$tmp"

  # Failure: no LOGFILE set
  if out="$(sh -c ". \"$ROOT_DIR/lib/common.sh\"; unset LOGFILE; require_logfile" 2>&1)"; then
    fail "require_logfile should fail when LOGFILE is unset"
  fi
  t_block "require_logfile (unset) output" "$out"
  assert_in "LOGFILE is not set" "$out"

  # Failure: LOGFILE points to non-existent file
  if out2="$(sh -c ". \"$ROOT_DIR/lib/common.sh\"; LOGFILE=/tmp/this-should-not-exist-$$; require_logfile" 2>&1)"; then
    fail "require_logfile should fail when LOGFILE does not exist"
  fi
  t_block "require_logfile (missing file) output" "$out2"
  assert_in "does not exist" "$out2"
  printf '\n'
}

test_add_title_with_explicit_title() {
  t_header "test_add_title_with_explicit_title"

  tmp="$(mktemp)"
  LOGFILE="$tmp"
  : >"$LOGFILE"

  add_title "My Title"

  content="$(cat "$LOGFILE")"
  t_block "Title block written" "$content"

  assert_in "My Title" "$content"
  assert_in "===================================" "$content"

  rm -f "$tmp"
  printf '\n'
}

test_add_comments_appends_stdin() {
  t_header "test_add_comments_appends_stdin"

  tmp="$(mktemp)"
  LOGFILE="$tmp"
  : >"$LOGFILE"

  add_title "Header"
  printf 'Line one\nLine two\n' | add_comments

  content="$(cat "$LOGFILE")"
  t_block "Comments block written" "$content"

  assert_in "Header" "$content"
  assert_in "Line one" "$content"
  assert_in "Line two" "$content"

  rm -f "$tmp"
  printf '\n'
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
  t_info "first_of returned: $first"
  assert_eq "sh" "$first"
  printf '\n'
}

test_run_executes_command() {
  t_header "test_run_executes_command"

  out="$(run printf 'hello-from-run')"
  t_info "run output: $out"
  assert_eq "hello-from-run" "$out"
  printf '\n'
}

test_detect_platform_and_arch() {
  t_header "test_detect_platform_and_arch"

  detect_platform
  detect_arch

  t_info "PLATFORM = $PLATFORM"
  t_info "ARCH     = $ARCH"

  case "$PLATFORM" in
  linux | macos) : ;;
  *) fail "Unexpected PLATFORM='$PLATFORM' (expected linux or macos)" ;;
  esac

  [ -n "$ARCH" ] || fail "ARCH should not be empty"
  printf '\n'
}

test_detect_distro() {
  t_header "test_detect_distro"

  detect_platform
  detect_distro

  t_info "PLATFORM = $PLATFORM"
  t_info "DISTRO   = $DISTRO"

  [ -n "$DISTRO" ] || fail "DISTRO should not be empty"
  printf '\n'
}

test_detect_pkg_manager() {
  t_header "test_detect_pkg_manager"

  detect_platform
  detect_distro
  detect_pkg_manager

  t_info "PLATFORM = $PLATFORM"
  t_info "DISTRO   = $DISTRO"
  t_info "PKG_MGR  = ${PKG_MGR:-<unset>}"

  case "${PKG_MGR:-none}" in
  apt | pacman | brew | none) : ;;
  *) fail "Unexpected PKG_MGR='$PKG_MGR' (expected apt/pacman/brew/none)" ;;
  esac
  printf '\n'
}

test_init_sudo_sets_var_or_warns() {
  t_header "test_init_sudo_sets_var_or_warns"

  init_sudo

  t_info "id -u = $(id -u)"
  t_info "SUDO  = ${SUDO:-<unset>}"

  : "${SUDO:-}" # ensure variable is defined
  printf '\n'
}

test_as_root_uses_run_when_root_or_no_sudo() {
  t_header "test_as_root_uses_run_when_root_or_no_sudo"

  CALLS=""
  run() {
    # shellcheck disable=SC2124
    CALLS="$CALLS|$*"
  }

  unset SUDO || true
  as_root echo "hello-as-root"

  pretty="${CALLS#|}"
  t_block "CALLS" "$pretty"
  assert_in "echo hello-as-root" "$pretty"
  printf '\n'
}

test_as_root_uses_sudo_when_set() {
  t_header "test_as_root_uses_sudo_when_set"

  CALLS=""
  run() {
    # shellcheck disable=SC2124
    CALLS="$CALLS|$*"
  }

  SUDO="fake-sudo"
  as_root echo "hello-via-sudo"

  pretty="${CALLS#|}"
  t_block "CALLS" "$pretty"

  if [ "$(id -u)" -eq 0 ]; then
    assert_in "echo hello-via-sudo" "$pretty"
  else
    assert_in "fake-sudo echo hello-via-sudo" "$pretty"
  fi
  printf '\n'
}

test_ensure_packages_with_apt_mocked() {
  t_header "test_ensure_packages_with_apt_mocked"

  PKG_MGR="apt"
  CALLS=""

  run() {
    # shellcheck disable=SC2124
    CALLS="$CALLS|$*"
  }

  SUDO=""
  as_root() {
    # shellcheck disable=SC2124
    CALLS="$CALLS|$*"
  }

  ensure_packages git curl

  pretty="${CALLS#|}"
  t_block "CALLS" "$(printf '%s\n' "$pretty" | tr '|' '\n')"

  assert_in "apt-get update -y" "$pretty"
  assert_in "apt-get install -y git curl" "$pretty"
  printf '\n'
}

test_ensure_packages_with_pacman_mocked() {
  t_header "test_ensure_packages_with_pacman_mocked"

  PKG_MGR="pacman"
  CALLS=""

  run() {
    # shellcheck disable=SC2124
    CALLS="$CALLS|$*"
  }

  SUDO=""
  as_root() {
    # shellcheck disable=SC2124
    CALLS="$CALLS|$*"
  }

  ensure_packages git curl

  pretty="${CALLS#|}"
  t_block "CALLS" "$(printf '%s\n' "$pretty" | tr '|' '\n')"

  assert_in "pacman -Sy --needed --noconfirm git curl" "$pretty"
  printf '\n'
}

test_ensure_packages_with_brew_mocked() {
  t_header "test_ensure_packages_with_brew_mocked"

  PKG_MGR="brew"
  CALLS=""

  run() {
    # shellcheck disable=SC2124
    CALLS="$CALLS|$*"
  }

  ensure_packages git curl

  pretty="${CALLS#|}"
  t_block "CALLS" "$(printf '%s\n' "$pretty" | tr '|' '\n')"

  assert_in "brew install git curl" "$pretty"
  printf '\n'
}

test_ensure_packages_with_none_does_not_crash() {
  t_header "test_ensure_packages_with_none_does_not_crash"

  PKG_MGR="none"
  CALLS=""
  WARNINGS=""

  run() {
    # shellcheck disable=SC2124
    CALLS="$CALLS|$*"
  }

  warn() {
    # shellcheck disable=SC2124
    WARNINGS="$WARNINGS|$*"
  }

  ensure_packages foo || fail "ensure_packages should not fail when PKG_MGR=none"

  calls_pretty="${CALLS#|}"
  warns_pretty="${WARNINGS#|}"

  t_block "CALLS" "$calls_pretty"
  t_block "WARNINGS" "$warns_pretty"

  [ -z "$calls_pretty" ] || fail "run() should not be called when PKG_MGR=none"
  assert_in "No supported package manager detected" "$warns_pretty"
  printf '\n'
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
  test_init_sudo_sets_var_or_warns
  test_as_root_uses_run_when_root_or_no_sudo
  test_as_root_uses_sudo_when_set
  test_ensure_packages_with_apt_mocked
  test_ensure_packages_with_pacman_mocked
  test_ensure_packages_with_brew_mocked
  test_ensure_packages_with_none_does_not_crash

  printf '────────────────────────────────────────────────────────\n'
  printf ' ALL TESTS PASSED\n'
  printf '────────────────────────────────────────────────────────\n'
}

main "$@"
