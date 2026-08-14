#!/bin/bash

# Usage: ./release_thin.sh <version>
# Example: ./release_thin.sh 1.0.1-rc1

MASTER_BRANCH="main"
DEVELOPMENT_BRANCH="development"
HARNESS_GIT_HOST="git0.harness.io"
HARNESS_UI_HOST="harness0.harness.io"

set -e

# Check if version parameter is provided
if [ -z "$1" ]; then
  echo "❌ Error: Version parameter is required"
  echo "Usage: ./release_thin.sh <version>"
  echo "Example: ./release_thin.sh 1.0.1-rc1"
  exit 1
fi

VERSION=$1
RELEASE_BRANCH="release/$VERSION"

# Ensure we're in the repo root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Origin must point at the Harness Code
ORIGIN_URL="$(git config --get remote.origin.url || true)"
case "$ORIGIN_URL" in
  *"$HARNESS_GIT_HOST"/*/*/*/* )
    HARNESS_PATH="${ORIGIN_URL#*://$HARNESS_GIT_HOST/}"
    HARNESS_PATH="${HARNESS_PATH%.git}"
    IFS='/' read -r HARNESS_ACCOUNT HARNESS_ORG HARNESS_PROJECT HARNESS_REPO <<< "$HARNESS_PATH"
    ;;
  * )
    echo "❌ Error: 'origin' is not a Harness Code repo on $HARNESS_GIT_HOST."
    echo "   Current origin: ${ORIGIN_URL:-<none>}"
    exit 1
    ;;
esac

if [ -z "${HARNESS_ACCOUNT:-}" ] || [ -z "${HARNESS_ORG:-}" ] || [ -z "${HARNESS_PROJECT:-}" ] || [ -z "${HARNESS_REPO:-}" ]; then
  echo "❌ Error: could not parse Harness Code coordinates from origin: $ORIGIN_URL"
  exit 1
fi

# Check if working directory is clean
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ Error: Working directory is not clean. Please commit or stash your changes first."
  exit 1
fi

# Fetch latest changes from remote
echo "📥 Fetching latest changes from remote..."
git fetch origin
CURRENT_BRANCH=$(git symbolic-ref --short HEAD)
echo "📑 Current branch: $CURRENT_BRANCH"
echo "📥 Pulling latest '$CURRENT_BRANCH' from origin..."
git pull --ff-only origin "$CURRENT_BRANCH"

# Create release branch from current branch
echo "🌿 Creating branch $RELEASE_BRANCH from $CURRENT_BRANCH..."
git checkout -B "$RELEASE_BRANCH"

# Any version with a "-" suffix (rc, beta, alpha...) is a pre-release
IS_PRERELEASE=false
if [[ "$VERSION" == *-* ]]; then
  IS_PRERELEASE=true
fi

# Update Version.swift
echo "📝 Updating Version.swift to $VERSION..."
VERSION_FILE="SplitThin/Common/Version.swift"
if ! grep -q 'private static let version = "[^"]*"' "$VERSION_FILE"; then
  echo "❌ Error: could not find version line in $VERSION_FILE"
  exit 1
fi
sed -i '' "s/private static let version = \".*\"/private static let version = \"$VERSION\"/" "$VERSION_FILE"

# Update CHANGES.txt if not a pre-release version
if [ "$IS_PRERELEASE" = false ]; then
  echo "📝 Updating CHANGES.txt..."
  echo ""
  echo "Please enter the changes for version $VERSION (one per line)"
  echo "Press Enter twice when done (or just press Enter to skip)"
  echo ""

  CHANGES=""
  while true; do
    read -r line

    # Break on empty line
    if [ -z "$line" ]; then
      if [ -z "$CHANGES" ]; then
        # No changes were entered, just break
        break
      else
        # Confirm if done
        read -r -p "Are you done entering changes? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
          break
        fi
      fi
    else
      # Add the line to changes
      if [ -z "$CHANGES" ]; then
        CHANGES="- $line"
      else
        # Real newline (not the literal "\n" chars), since BSD sed's replacement
        # text doesn't translate "\n" the way GNU sed's does.
        CHANGES="$CHANGES"$'\n'"- $line"
      fi
    fi
  done

  # Create the new entry
  CURRENT_DATE=$(LC_ALL=C date "+%b %-d, %Y")
  NEW_ENTRY="$VERSION ($CURRENT_DATE)"
  if [ -n "$CHANGES" ]; then
    NEW_ENTRY="$NEW_ENTRY"$'\n'"$CHANGES"
  fi

  # Prepend via printf+cat instead of sed, so we don't depend on sed's (BSD vs
  # GNU) handling of escape sequences in the replacement text.
  CHANGES_TMP="$(mktemp)"
  { printf '%s\n\n' "$NEW_ENTRY"; cat CHANGES.txt; } > "$CHANGES_TMP"
  mv "$CHANGES_TMP" CHANGES.txt
fi

# Commit 
echo "💾 Committing changes..."
if [ "$IS_PRERELEASE" = false ]; then
  git add SplitThin/Common/Version.swift CHANGES.txt
  git commit -m "chore: Update version to $VERSION and update CHANGES.txt"
else
  git add SplitThin/Common/Version.swift
  git commit -m "chore: Update version to $VERSION"
fi

# Push 
echo "📤 Pushing branch to remote..."
git push origin "$RELEASE_BRANCH"

# Determine target branch based on pre-release status
if [ "$IS_PRERELEASE" = true ]; then
  TARGET_BRANCH="$DEVELOPMENT_BRANCH"
  echo "📊 Pre-release version detected, PR will target the $DEVELOPMENT_BRANCH branch"
else
  TARGET_BRANCH="$MASTER_BRANCH"
  echo "📊 Regular version detected, PR will target the $MASTER_BRANCH branch"
fi

# Create-PR
PR_URL="https://$HARNESS_UI_HOST/ng/account/$HARNESS_ACCOUNT/all/code/orgs/$HARNESS_ORG/projects/$HARNESS_PROJECT/repos/$HARNESS_REPO/pulls/compare/$TARGET_BRANCH...$RELEASE_BRANCH"

echo ""
echo "🎉 Release preparation completed successfully!"
echo ""
echo "Opening browser to create pull request..."
open "$PR_URL" 2>/dev/null || echo "Open this URL to create the PR: $PR_URL"
echo ""
echo "Next steps:"
echo "1. Complete the pull request to merge $RELEASE_BRANCH into $TARGET_BRANCH in Harness Code."
echo "2. After merging, the release-tag pipeline in Harness creates and pushes the tag '$VERSION'."
echo ""
