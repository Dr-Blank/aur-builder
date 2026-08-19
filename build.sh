#!/bin/bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo}"
REPO_NAME="${REPO_NAME:-repo}"
PACKAGES_FILE="${PACKAGES_FILE:-/packages.txt}"
USE_CHROOT="${USE_CHROOT:-1}"
SKIP_PGP_CHECK="${SKIP_PGP_CHECK:-0}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "=== AUR Builder starting ==="
log "REPO_DIR=$REPO_DIR"
log "REPO_NAME=$REPO_NAME"
log "USE_CHROOT=$USE_CHROOT"
log "SKIP_PGP_CHECK=$SKIP_PGP_CHECK"
log "EXTRA_PACKAGES=${EXTRA_PACKAGES:-<none>}"

if [ "$USE_CHROOT" = "0" ] && [ -z "${MAKEFLAGS:-}" ]; then
    export MAKEFLAGS="-j$(nproc)"
elif [ -n "${MAKEFLAGS:-}" ]; then
    export MAKEFLAGS
fi

log "MAKEFLAGS=${MAKEFLAGS:-<unset>}"

sudo chown -R builder:builder "$REPO_DIR"
find "$REPO_DIR" -name "*.lck" -delete

if [ ! -f "${REPO_DIR}/${REPO_NAME}.db" ]; then
    log "No repo DB found, initializing: ${REPO_DIR}/${REPO_NAME}.db"
    repo-add "${REPO_DIR}/${REPO_NAME}.db.tar.gz"
fi

log "Syncing pacman databases..."
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
    log "No packages specified. Mount packages.txt or set PACKAGES env var."
    exit 0
fi

log "Packages to build (${#pkgs[@]}): ${pkgs[*]}"

build_args=(
    --database "$REPO_NAME"
    --root "$REPO_DIR"
    --no-view
    --no-confirm
)

if [ "$USE_CHROOT" = "1" ]; then
    log "Build mode: clean chroot"
    build_args+=(--chroot)
    if [ -n "$EXTRA_PACKAGES" ]; then
        log "Seeding chroot with extra packages: $EXTRA_PACKAGES"
        aur chroot -c -- $EXTRA_PACKAGES
    fi
else
    log "Build mode: no chroot"
    if [ -n "$EXTRA_PACKAGES" ]; then
        log "Installing extra packages (no-chroot mode): $EXTRA_PACKAGES"
        sudo pacman -S --noconfirm --needed $EXTRA_PACKAGES
    fi
fi

if [ "$SKIP_PGP_CHECK" = "1" ]; then
    log "PGP signature checks: disabled (SKIP_PGP_CHECK=1)"
    build_args+=(--makepkg-args --skippgpcheck)
fi

log "aur sync args: ${build_args[*]}"
log "--- aur sync output ---"
aur sync "${build_args[@]}" "${pkgs[@]}" || { rc=$?; log "ERROR: aur sync failed (exit ${rc})"; exit "${rc}"; }
log "--- aur sync done ---"

log "=== Build complete ==="
