#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$ROOT_DIR/.harness/scripts"
TOOLS_DIR="$SCRIPT_DIR/_tools"
REPORTS_ROOT="${REPORTS_ROOT:-$ROOT_DIR/.reports}"
CI_HOME="${CI_HOME:-$ROOT_DIR/.ci-home}"
MODULE_CACHE_DIR="${MODULE_CACHE_DIR:-$ROOT_DIR/.build/ModuleCache.noindex}"

# Ensure REPORTS_ROOT is absolute so report paths still resolve correctly after `cd` into each package.
if [[ "$REPORTS_ROOT" != /* ]]; then
  REPORTS_ROOT="$ROOT_DIR/$REPORTS_ROOT"
fi

log() {
  printf '[run-ci-reports] %s\n' "$*"
}

die() {
  printf '[run-ci-reports] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

swift_local() {
  HOME="$CI_HOME" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swift "$@"
}

TEST_TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-900}"
CI_KEYCHAIN=""

# Send a signal to a process and all its descendants (children first, so they cannot be re-parented away).
kill_tree() {
  local sig="$1" pid="$2" child
  for child in $(pgrep -P "$pid" 2>/dev/null || true); do
    kill_tree "$sig" "$child"
  done
  kill "-$sig" "$pid" 2>/dev/null || true
}

# Run a command with a time limit (macOS has no GNU timeout by default).
# Output of the command must already be redirected by the caller. Returns 124 on timeout.
run_with_timeout() {
  local secs="$1"
  shift
  local flag cmd_pid wd_pid rc
  flag="$(mktemp)"
  "$@" &
  cmd_pid=$!
  (
    sleep "$secs"
    echo timeout >"$flag"
    kill_tree TERM "$cmd_pid"
    sleep 5
    kill_tree KILL "$cmd_pid"
  ) &
  wd_pid=$!
  rc=0
  wait "$cmd_pid" || rc=$?
  kill_tree TERM "$wd_pid"
  wait "$wd_pid" 2>/dev/null || true
  if [[ -s "$flag" ]]; then
    rc=124
  fi
  rm -f "$flag"
  return "$rc"
}

# CI only: give HOME="$CI_HOME" a default unlocked keychain so keychain tests do not raise a modal dialog.
# Every `security` call uses HOME="$CI_HOME"; never touches the real HOME (guarded below).
setup_ci_keychain() {
  local ci_flag
  ci_flag="$(printf '%s' "${CI:-}" | tr '[:upper:]' '[:lower:]')"
  if [[ -z "${HARNESS_BUILD_ID:-}" && "$ci_flag" != "true" && "$ci_flag" != "1" ]]; then
    log "Not in CI (no HARNESS_BUILD_ID/CI): skipping temporary keychain"
    return 0
  fi
  if [[ "$CI_HOME" == "${HOME:-}" ]]; then
    log "CI_HOME equals the real HOME: skipping temporary keychain"
    return 0
  fi
  command -v security >/dev/null 2>&1 || { log "security not found: skipping temporary keychain"; return 0; }

  CI_KEYCHAIN="$CI_HOME/Library/Keychains/ci-temp.keychain-db"
  mkdir -p "$CI_HOME/Library/Keychains"
  # Remove a stale keychain (and its list entry) left by an earlier killed run.
  HOME="$CI_HOME" security delete-keychain "$CI_KEYCHAIN" >/dev/null 2>&1 || true
  rm -f "$CI_KEYCHAIN"
  HOME="$CI_HOME" security create-keychain -p "ci-temp" "$CI_KEYCHAIN"
  HOME="$CI_HOME" security set-keychain-settings -lut 3600 "$CI_KEYCHAIN"
  HOME="$CI_HOME" security unlock-keychain -p "ci-temp" "$CI_KEYCHAIN"
  HOME="$CI_HOME" security default-keychain -s "$CI_KEYCHAIN"
  HOME="$CI_HOME" security list-keychains -d user -s "$CI_KEYCHAIN"
  log "Temporary keychain ready: $CI_KEYCHAIN"
}

cleanup_ci_keychain() {
  if [[ -n "$CI_KEYCHAIN" ]]; then
    HOME="$CI_HOME" security delete-keychain "$CI_KEYCHAIN" >/dev/null 2>&1 || true
    rm -f "$CI_KEYCHAIN"
  fi
}

discover_packages() {
  local submodules=()

  # Best-effort: detect git submodules to avoid running their tests / coverage as part of the thin client pipeline.
  # (We still need the submodule checked out for SwiftPM local dependencies.)
  if [[ -f "$ROOT_DIR/.gitmodules" ]]; then
    while IFS= read -r sm_path; do
      [[ -n "$sm_path" ]] && submodules+=("$sm_path")
    done < <(git -C "$ROOT_DIR" config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}' || true)
  fi

  # Always ignore ios-client (even if it isn't registered as a submodule yet).
  submodules+=("ios-client")

  find "$ROOT_DIR" -type f -name "Package.swift" -not -path "*/.build/*" -print0 \
    | while IFS= read -r -d '' package_manifest; do
        package_dir="$(dirname "$package_manifest")"

        # Skip any package that lives under a submodule path.
        for sm in "${submodules[@]}"; do
          sm="${sm%/}"
          if [[ -n "$sm" ]] && [[ "$package_dir" == "$ROOT_DIR/$sm"* ]]; then
            continue 2
          fi
        done

        printf '%s\n' "$package_dir"
      done | sort -u
}

package_slug() {
  local package_dir="$1"
  local rel="${package_dir#$ROOT_DIR/}"
  if [[ "$rel" == "$package_dir" ]]; then
    rel="$(basename "$package_dir")"
  fi
  rel="${rel//\//_}"
  if [[ -z "$rel" ]]; then
    rel="root"
  fi
  printf '%s\n' "$rel"
}

find_profdata() {
  local package_dir="$1"
  find "$package_dir/.build" -type f -name default.profdata | head -n 1
}

find_test_binary() {
  local package_dir="$1"
  find "$package_dir/.build" -type f -name '*PackageTests' -perm -111 | head -n 1
}

run_for_package() {
  local package_dir="$1"
  local slug="$2"
  local out_dir="$REPORTS_ROOT/$slug"
  local test_log="$out_dir/swift-test.log"
  local junit_xml="$out_dir/junit.xml"
  local llvm_cov_json="$out_dir/llvm-cov.json"
  local sonar_xml="$out_dir/sonarqube-generic-coverage.xml"
  local profdata test_bin

  mkdir -p "$out_dir"
  log "Running package: $package_dir"

  # One test run with coverage; log goes to the file and is streamed to the Harness log.
  local test_rc=0 tail_pid
  : >"$test_log"
  tail -n +1 -f "$test_log" &
  tail_pid=$!
  (
    cd "$package_dir" || exit 1
    run_with_timeout "$TEST_TIMEOUT_SECS" swift_local test --enable-code-coverage >"$test_log" 2>&1
  ) || test_rc=$?
  sleep 1
  kill "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true
  if [[ "$test_rc" -eq 124 ]]; then
    log "swift test timed out after ${TEST_TIMEOUT_SECS}s (log above)"
  fi

  python3 "$TOOLS_DIR/swift_test_to_junit.py" \
    --input "$test_log" \
    --output "$junit_xml" || [[ "$test_rc" -ne 0 ]]
  [[ "$test_rc" -eq 0 ]] || die "swift test failed (exit $test_rc) for package: $package_dir"

  profdata="$(find_profdata "$package_dir")"
  [[ -n "$profdata" && -f "$profdata" ]] || die "Coverage profile not found for package: $package_dir"

  test_bin="$(find_test_binary "$package_dir")"
  [[ -n "$test_bin" && -f "$test_bin" ]] || die "Package test binary not found for package: $package_dir"

  xcrun llvm-cov export "$test_bin" -instr-profile "$profdata" >"$llvm_cov_json"
  xcrun llvm-cov export "$test_bin" -instr-profile "$profdata" -format=lcov >"$out_dir/lcov.info"
  mkdir -p "$ROOT_DIR/coverage"
  cat "$out_dir/lcov.info" >>"$ROOT_DIR/coverage/lcov.info"

  python3 "$TOOLS_DIR/swift_coverage_to_sonar_generic.py" \
    --input "$llvm_cov_json" \
    --output "$sonar_xml" \
    --repo-root "$ROOT_DIR"

  log "Reports generated in: $out_dir"
}

main() {
  require_cmd "swift"
  require_cmd "python3"
  require_cmd "xcrun"

  [[ -f "$TOOLS_DIR/swift_test_to_junit.py" ]] || die "Missing converter: $TOOLS_DIR/swift_test_to_junit.py"
  [[ -f "$TOOLS_DIR/swift_coverage_to_sonar_generic.py" ]] || die "Missing converter: $TOOLS_DIR/swift_coverage_to_sonar_generic.py"

  packages=()
  while IFS= read -r package_dir; do
    packages+=("$package_dir")
  done < <(discover_packages)
  [[ "${#packages[@]}" -gt 0 ]] || die "No Package.swift files found under repository root."

  mkdir -p "$REPORTS_ROOT"
  mkdir -p "$ROOT_DIR/coverage"
  : >"$ROOT_DIR/coverage/lcov.info"
  mkdir -p "$CI_HOME" "$MODULE_CACHE_DIR"
  trap cleanup_ci_keychain EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  setup_ci_keychain
  log "Reports root: $REPORTS_ROOT"

  for package_dir in "${packages[@]}"; do
    run_for_package "$package_dir" "$(package_slug "$package_dir")"
  done

  log "Done."
}

main "$@"
