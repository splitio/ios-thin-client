#!/bin/bash

# ios-thin-client Release Preparation Script
# Mirrors ios-client/scripts/release.sh.
# Usage: ./release_thin.sh <version>
# Example: ./release_thin.sh 1.0.1-rc1

# Branch name constants - update these if branch naming changes
MASTER_BRANCH="main"
DEVELOPMENT_BRANCH="development"

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

# Check if working directory is clean
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ Error: Working directory is not clean. Please commit or stash your changes first."
  exit 1
fi

# Fetch latest changes from remote
echo "📥 Fetching latest changes from remote..."
git fetch origin

# Get current branch
CURRENT_BRANCH=$(git symbolic-ref --short HEAD)
echo "📑 Current branch: $CURRENT_BRANCH"

# Create release branch from current branch
echo "🌿 Creating branch $RELEASE_BRANCH from $CURRENT_BRANCH..."
git checkout -b "$RELEASE_BRANCH"

# Any version with a "-" suffix (rc, beta, alpha...) is a pre-release
IS_PRERELEASE=false
if [[ "$VERSION" == *-* ]]; then
  IS_PRERELEASE=true
fi

# Update Version.swift
echo "📝 Updating Version.swift to $VERSION..."
sed -i '' "s/private static let version = \".*\"/private static let version = \"$VERSION\"/" SplitThin/Common/Version.swift

# Update CHANGES.txt if not a pre-release version
if [ "$IS_PRERELEASE" = false ]; then
  echo "📝 Updating CHANGES.txt..."

  # Prompt for changes
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
        CHANGES="$CHANGES\n- $line"
      fi
    fi
  done

  # Create the new entry
  CURRENT_DATE=$(LC_ALL=C date "+%b %-d, %Y")
  NEW_ENTRY="$VERSION ($CURRENT_DATE)"
  if [ -n "$CHANGES" ]; then
    NEW_ENTRY="$NEW_ENTRY\n$CHANGES"
  fi

  # Insert at the beginning of the file
  sed -i '' "1s/^/$NEW_ENTRY\n\n/" CHANGES.txt
fi

# Commit changes
echo "💾 Committing changes..."
if [ "$IS_PRERELEASE" = false ]; then
  git add SplitThin/Common/Version.swift CHANGES.txt
  git commit -m "chore: Update version to $VERSION and update CHANGES.txt"
else
  git add SplitThin/Common/Version.swift
  git commit -m "chore: Update version to $VERSION"
fi

# Push changes
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

echo ""
echo "🎉 Release preparation completed successfully!"
echo ""
echo "Next steps:"
echo "1. Open Harness Code (repo ios-thin-client, org PROD, project Harness_Split)"
echo "   and create a PR from '$RELEASE_BRANCH' into '$TARGET_BRANCH'."
echo "2. After merging, the tag '$VERSION' is created and mirrored to GitHub."
echo ""
