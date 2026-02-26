#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$ROOT_DIR/.harness/scripts"
TOOLS_DIR="$SCRIPT_DIR/_tools"
REPORTS_ROOT="${REPORTS_ROOT:-$ROOT_DIR/.reports}"
CI_HOME="${CI_HOME:-$ROOT_DIR/.ci-home}"
MODULE_CACHE_DIR="${MODULE_CACHE_DIR:-$ROOT_DIR/.build/ModuleCache.noindex}"

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

discover_packages() {
  find "$ROOT_DIR" -type f -name "Package.swift" -not -path "*/.build/*" -print0 \
    | while IFS= read -r -d '' package_manifest; do
        dirname "$package_manifest"
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

  (
    cd "$package_dir"
    swift_local test >"$test_log" 2>&1
  )

  python3 "$TOOLS_DIR/swift_test_to_junit.py" \
    --input "$test_log" \
    --output "$junit_xml"

  (
    cd "$package_dir"
    swift_local test --enable-code-coverage >/dev/null
  )

  profdata="$(find_profdata "$package_dir")"
  [[ -n "$profdata" && -f "$profdata" ]] || die "Coverage profile not found for package: $package_dir"

  test_bin="$(find_test_binary "$package_dir")"
  [[ -n "$test_bin" && -f "$test_bin" ]] || die "Package test binary not found for package: $package_dir"

  xcrun llvm-cov export "$test_bin" -instr-profile "$profdata" >"$llvm_cov_json"

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
  mkdir -p "$CI_HOME" "$MODULE_CACHE_DIR"
  log "Reports root: $REPORTS_ROOT"

  for package_dir in "${packages[@]}"; do
    run_for_package "$package_dir" "$(package_slug "$package_dir")"
  done

  log "Done."
}

main "$@"
