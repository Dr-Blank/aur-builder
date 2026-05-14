#!/bin/bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo}"
REPO_NAME="${REPO_NAME:-repo}"
PACKAGES_FILE="${PACKAGES_FILE:-/packages.txt}"
USE_CHROOT="${USE_CHROOT:-1}"
SKIP_PGP_CHECK="${SKIP_PGP_CHECK:-0}"

if [ "$USE_CHROOT" = "0" ] && [ -z "${MAKEFLAGS:-}" ]; then
    export MAKEFLAGS="-j$(nproc)"
elif [ -n "${MAKEFLAGS:-}" ]; then
    export MAKEFLAGS
fi

sudo chown -R builder:builder "$REPO_DIR"
find "$REPO_DIR" -name "*.lck" -delete

if [ ! -f "${REPO_DIR}/${REPO_NAME}.db" ]; then
    repo-add "${REPO_DIR}/${REPO_NAME}.db.tar.gz"
fi

sudo pacman -Sy --noconfirm

declare -A seen
pkgs=()

if [ -f "$PACKAGES_FILE" ]; then
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line//[[:space:]]/}"
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

if [ "$SKIP_PGP_CHECK" = "1" ]; then
    echo "Warning: PGP signature checks disabled (SKIP_PGP_CHECK=1)"
    build_args+=(--makepkg-args --skippgpcheck)
fi

aur sync "${build_args[@]}" "${pkgs[@]}"
