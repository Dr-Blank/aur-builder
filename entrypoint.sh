#!/bin/bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo}"
REPO_NAME="${REPO_NAME:-repo}"
PACKAGES_FILE="${PACKAGES_FILE:-/packages.txt}"

# Initialize empty repo db if not present
if [ ! -f "${REPO_DIR}/${REPO_NAME}.db" ]; then
    repo-add "${REPO_DIR}/${REPO_NAME}.db.tar.gz"
fi

# Collect packages from file and env var, skip blanks and comments
declare -A seen
pkgs=()

if [ -f "$PACKAGES_FILE" ]; then
    while IFS= read -r line; do
        line="${line%%#*}"   # strip inline comments
        line="${line//[[:space:]]/}"  # strip whitespace
        [[ -z "$line" ]] && continue
        if [[ -z "${seen[$line]+x}" ]]; then
            seen[$line]=1
            pkgs+=("$line")
        fi
    done < "$PACKAGES_FILE"
fi

if [ -n "${PACKAGES:-}" ]; then
    for pkg in $PACKAGES; do
        [[ -z "$pkg" ]] && continue
        if [[ -z "${seen[$pkg]+x}" ]]; then
            seen[$pkg]=1
            pkgs+=("$pkg")
        fi
    done
fi

if [ ${#pkgs[@]} -eq 0 ]; then
    echo "No packages specified. Mount packages.txt or set PACKAGES env var."
    exit 0
fi

echo "Building ${#pkgs[@]} package(s): ${pkgs[*]}"

aur sync \
    --database "$REPO_NAME" \
    --root "$REPO_DIR" \
    --no-view \
    --no-confirm \
    --chroot \
    "${pkgs[@]}"
