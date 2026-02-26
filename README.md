# SplitThin

## Requirements

- Xcode 15+ or Swift 5.5+
- macOS (for local CLI test/coverage commands)

## Build & Test

From the repository root:

```bash
swift build
swift test
```

## Usage

```swift
import SplitThin

SplitThinMain.main()
```

## Local Coverage Report

```bash
swift test --enable-code-coverage
PROFDATA=$(find .build -type f -name default.profdata | head -n 1)
TEST_BIN=$(find .build -type f -name '*PackageTests' -perm -111 | head -n 1)
xcrun llvm-cov report "$TEST_BIN" -instr-profile "$PROFDATA"
```

## Pre-commit Coverage Gate

Set repository hooks path once:

```bash
git config core.hooksPath .githooks
```

Run manually:

```bash
.githooks/pre-commit
```

Default threshold is `80%`. Override with:

```bash
COVERAGE_THRESHOLD=85 .githooks/pre-commit
```

