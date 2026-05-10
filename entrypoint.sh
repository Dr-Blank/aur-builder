#!/bin/bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo}"
REPO_NAME="${REPO_NAME:-repo}"
PACKAGES_FILE="${PACKAGES_FILE:-/packages.txt}"
USE_CHROOT="${USE_CHROOT:-1}"

# In fast/no-chroot mode use all cores automatically; production mode respects
# user-set MAKEFLAGS or falls back to makepkg defaults (set MAKEFLAGS=-jN to override)
if [ "$USE_CHROOT" = "0" ] && [ -z "${MAKEFLAGS:-}" ]; then
    export MAKEFLAGS="-j$(nproc)"
elif [ -n "${MAKEFLAGS:-}" ]; then
    export MAKEFLAGS
fi

# Fix ownership of mounted repo dir (host may create it as root)
sudo chown -R builder:builder "$REPO_DIR"

# Remove stale lockfiles left by interrupted runs
find "$REPO_DIR" -name "*.lck" -delete

# Initialize empty repo db if not present
if [ ! -f "${REPO_DIR}/${REPO_NAME}.db" ]; then
    repo-add "${REPO_DIR}/${REPO_NAME}.db.tar.gz"
fi

# Sync package databases so pacman can resolve deps (including local [repo])
sudo pacman -Sy --noconfirm

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

build_args=(
    --database "$REPO_NAME"
    --root "$REPO_DIR"
    --no-view
    --no-confirm
)

if [ "$USE_CHROOT" = "1" ]; then
    echo "Building ${#pkgs[@]} package(s) [clean chroot]: ${pkgs[*]}"
    build_args+=(--chroot)
else
    echo "Building ${#pkgs[@]} package(s) [no chroot]: ${pkgs[*]}"
fi

aur sync "${build_args[@]}" "${pkgs[@]}"
