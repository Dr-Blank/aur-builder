#!/bin/bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo}"
REPO_NAME="${REPO_NAME:-repo}"
PACKAGES_FILE="${PACKAGES_FILE:-/packages.txt}"
USE_CHROOT="${USE_CHROOT:-1}"
SKIP_PGP_CHECK="${SKIP_PGP_CHECK:-0}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"
CHECK_STALE_DEPS="${CHECK_STALE_DEPS:-1}"
STALE_EXCLUDE="${STALE_EXCLUDE:-}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# aur sync only rebuilds when the AUR version changes. That check is blind to
# soname bumps in dependencies: Arch moves libfoo.so.3 to libfoo.so.4, the AUR
# pkgver stays put, and the package already in the repo keeps linking against a
# soname nothing provides any more. It stays uninstallable until forced.
#
# Detection: read each repo package's recorded depends and test whether every
# one still resolves against the synced databases. pacman -Sddp resolves
# provisions and sonames; pacman -T cannot be used here, as it only tests
# against installed packages, and almost nothing is installed in this container.
detect_stale_packages() {
    local pkg dep deps base ver broken
    local -A excluded=()

    for pkg in $STALE_EXCLUDE; do
        excluded["$pkg"]=1
    done

    while read -r _ pkg _; do
        [[ -n "${excluded[$pkg]+x}" ]] && continue

        deps=$(expac -S '%D' "${REPO_NAME}/${pkg}" 2>/dev/null) || continue
        [[ -z "$deps" ]] && continue

        # Fast path: all deps resolve together, nothing to do.
        # shellcheck disable=SC2086
        pacman -Sddp --noconfirm -- $deps >/dev/null 2>&1 && continue

        # Slow path only on failure: find which deps are actually unresolvable.
        # An aggregate failure can also come from deps that conflict with each
        # other, so a package with no individually-broken dep is not stale.
        broken=""
        for dep in $deps; do
            pacman -Sddp --noconfirm -- "$dep" >/dev/null 2>&1 || broken+=" $dep"
        done
        [[ -z "$broken" ]] && continue

        base=$(expac -S '%e' "${REPO_NAME}/${pkg}" 2>/dev/null) || base="$pkg"
        [[ -z "$base" ]] && base="$pkg"
        [[ -n "${excluded[$base]+x}" ]] && continue

        ver=$(expac -S '%v' "${REPO_NAME}/${pkg}" 2>/dev/null) || ver=""
        log "STALE: ${pkg} ${ver} (pkgbase ${base}) unsatisfiable:${broken}" >&2
        printf '%s\t%s\n' "$base" "$ver"
    done < <(pacman -Sl "$REPO_NAME" 2>/dev/null || true)
}

# A rebuild alone fixes the repo but not the clients: the version string is
# unchanged, so pacman -Syu on a machine holding the broken package sees
# nothing to upgrade. Bumping pkgrel to the N.M form Arch itself uses for
# rebuilds makes the fix reach clients, and a later real AUR bump still wins
# (vercmp 9.0.1-2 > 9.0.1-1.1).
bump_pkgrel() {
    local rel="${1##*-}"

    if [[ "$rel" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        printf '%s.%s\n' "${BASH_REMATCH[1]}" "$(( BASH_REMATCH[2] + 1 ))"
    else
        printf '%s.1\n' "$rel"
    fi
}

rebuild_stale_packages() {
    local aurdest="${AURDEST:-${XDG_CACHE_HOME:-$HOME/.cache}/aurutils/sync}"
    local base ver new_rel rc=0
    local -A stale=()
    local -a rebuild_args=()

    log "Checking repo packages for unsatisfiable dependencies..."

    while IFS=$'\t' read -r base ver; do
        [[ -z "$base" ]] && continue
        stale["$base"]="$ver"
    done < <(detect_stale_packages)

    if [ ${#stale[@]} -eq 0 ]; then
        log "No stale packages found."
        return 0
    fi

    log "Force-rebuilding ${#stale[@]} stale pkgbase(s): ${!stale[*]}"

    rebuild_args=(
        --database "$REPO_NAME"
        --root "$REPO_DIR"
        --force
        --no-confirm
    )
    [ "$USE_CHROOT" = "1" ] && rebuild_args+=(--chroot)
    [ "$SKIP_PGP_CHECK" = "1" ] && rebuild_args+=(--makepkg-args --skippgpcheck)

    mkdir -p "$aurdest"

    for base in "${!stale[@]}"; do
        ver="${stale[$base]}"
        new_rel=$(bump_pkgrel "$ver")

        log "Rebuilding ${base} (${ver} -> pkgrel ${new_rel})"

        if ! ( cd "$aurdest" && aur fetch --reset -- "$base" ); then
            log "ERROR: aur fetch failed for ${base}"
            rc=1
            continue
        fi

        if ! sed -i -E "s/^pkgrel=.*/pkgrel=${new_rel}/" "${aurdest}/${base}/PKGBUILD" \
            || ! grep -qE "^pkgrel=${new_rel}\$" "${aurdest}/${base}/PKGBUILD"; then
            log "ERROR: could not set pkgrel in ${base}/PKGBUILD, skipping"
            git -C "${aurdest}/${base}" checkout -- PKGBUILD 2>/dev/null || true
            rc=1
            continue
        fi

        if ( cd "${aurdest}/${base}" && aur build "${rebuild_args[@]}" ); then
            log "Rebuilt ${base}"
        else
            log "ERROR: rebuild failed for ${base}"
            rc=1
        fi

        # Leave the clone clean so the next aur fetch/sync is not patched twice.
        git -C "${aurdest}/${base}" checkout -- PKGBUILD 2>/dev/null || true
    done

    return "$rc"
}

log "=== AUR Builder starting ==="
log "REPO_DIR=$REPO_DIR"
log "REPO_NAME=$REPO_NAME"
log "USE_CHROOT=$USE_CHROOT"
log "SKIP_PGP_CHECK=$SKIP_PGP_CHECK"
log "EXTRA_PACKAGES=${EXTRA_PACKAGES:-<none>}"
log "CHECK_STALE_DEPS=$CHECK_STALE_DEPS"
log "STALE_EXCLUDE=${STALE_EXCLUDE:-<none>}"

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
if [ "$USE_CHROOT" = "0" ]; then
    # makepkg installs build deps straight into this container. Syncing the
    # databases without upgrading leaves a partial-upgrade state, which breaks
    # as soon as a new dep conflicts with an older installed package.
    # The chroot path does not need this: aur chroot updates its own container.
    sudo pacman -Syu --noconfirm
else
    sudo pacman -Sy --noconfirm
fi

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

# Runs after the sync so genuine version bumps are handled by the normal path,
# and only packages still broken afterwards get a forced rebuild.
stale_rc=0
if [ "$CHECK_STALE_DEPS" = "1" ]; then
    rebuild_stale_packages || stale_rc=$?
else
    log "Stale dependency check: disabled (CHECK_STALE_DEPS=0)"
fi

if [ "$stale_rc" -ne 0 ]; then
    log "=== Build complete, with stale-package rebuild failures ==="
    exit "$stale_rc"
fi

log "=== Build complete ==="
