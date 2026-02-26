#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$ROOT_DIR/.harness/scripts"
TOOLS_DIR="$SCRIPT_DIR/_tools"
CI_HOME="${CI_HOME:-$ROOT_DIR/.ci-home}"
MODULE_CACHE_DIR="${MODULE_CACHE_DIR:-$ROOT_DIR/.build/ModuleCache.noindex}"

log() {
  printf '[install-deps] %s\n' "$*"
}

die() {
  printf '[install-deps] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  local help_msg="${2:-Install '$cmd' and retry.}"
  command -v "$cmd" >/dev/null 2>&1 || die "$help_msg"
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

assert_host() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  if [[ "$os" != "Darwin" ]]; then
    die "This script expects macOS (Darwin). Current OS: $os"
  fi

  if [[ "$arch" != "arm64" ]]; then
    log "Warning: expected arm64 host, got '$arch'. Continuing for local usage."
  fi
}

main() {
  assert_host

  require_cmd "swift" "Swift toolchain is missing (install Xcode or Swift toolchain)."
  require_cmd "python3" "python3 is required for test/coverage report converters."
  require_cmd "xcode-select" "Xcode Command Line Tools are required."
  require_cmd "xcrun" "xcrun is required (install Xcode Command Line Tools)."
  require_cmd "git" "git is required."

  xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools not configured. Run: xcode-select --install"
  xcrun --find llvm-cov >/dev/null 2>&1 || die "llvm-cov not found via xcrun."
  xcrun --find llvm-profdata >/dev/null 2>&1 || die "llvm-profdata not found via xcrun."

  [[ -f "$TOOLS_DIR/swift_test_to_junit.py" ]] || die "Missing converter: $TOOLS_DIR/swift_test_to_junit.py"
  [[ -f "$TOOLS_DIR/swift_coverage_to_sonar_generic.py" ]] || die "Missing converter: $TOOLS_DIR/swift_coverage_to_sonar_generic.py"
  [[ -f "$SCRIPT_DIR/run-ci-reports.sh" ]] || die "Missing runner script: $SCRIPT_DIR/run-ci-reports.sh"

  chmod +x \
    "$SCRIPT_DIR/install-deps.sh" \
    "$SCRIPT_DIR/run-ci-reports.sh" \
    "$TOOLS_DIR/swift_test_to_junit.py" \
    "$TOOLS_DIR/swift_coverage_to_sonar_generic.py"

  log "Swift version: $(swift --version | head -n 1)"
  log "Discovering Swift packages under $ROOT_DIR"

  mkdir -p "$CI_HOME" "$MODULE_CACHE_DIR"

  packages=()
  while IFS= read -r package_dir; do
    packages+=("$package_dir")
  done < <(discover_packages)
  [[ "${#packages[@]}" -gt 0 ]] || die "No Package.swift files found under repository root."

  for pkg in "${packages[@]}"; do
    log "Package: $pkg"
  done

  # Warm dependency resolution for all package roots so CI test/report steps are faster.
  for pkg in "${packages[@]}"; do
    log "Resolving package dependencies in: $pkg"
    (cd "$pkg" && swift_local package resolve)
  done

  cat <<'EOF'
[install-deps] Environment is ready.
[install-deps] Run everything with one command:
[install-deps]   .harness/scripts/run-ci-reports.sh
[install-deps] Optional:
[install-deps]   REPORTS_ROOT=.reports .harness/scripts/run-ci-reports.sh
EOF
}

main "$@"
