#!/bin/bash
set -euo pipefail

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    read -rp "Version (e.g. 1.0.0): " VERSION
fi

# Strip leading v if provided
VERSION="${VERSION#v}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: invalid version '$VERSION' — use semver (e.g. 1.0.0)" >&2
    exit 1
fi

TAG="v${VERSION}"

# Warn if not on main
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
    echo "Warning: not on main branch (current: $BRANCH)"
    read -rp "Continue? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

# Bail on uncommitted changes
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: uncommitted changes — commit or stash first" >&2
    exit 1
fi

# Bail if tag exists
if git tag | grep -qx "$TAG"; then
    echo "Error: tag $TAG already exists" >&2
    exit 1
fi

git tag "$TAG" -m "Release $TAG"
git push origin "$TAG"

REPO=$(git remote get-url origin | sed 's|.*github\.com[:/]||' | sed 's|\.git$||')
IMAGE="ghcr.io/${REPO,,}"

echo ""
echo "Released $TAG — GitHub Actions will push:"
echo "  ${IMAGE}:${VERSION}"
echo "  ${IMAGE}:latest"
echo ""
echo "  https://github.com/${REPO}/actions"
