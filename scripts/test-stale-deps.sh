#!/bin/bash
# Tests for the stale dependency check in build.sh.
#
# Runs inside the aur-builder image, where pacman, expac and aurutils exist:
#   docker run --rm -v "$PWD/build.sh:/build.sh:ro" \
#       -v "$PWD/scripts/test-stale-deps.sh:/test.sh:ro" \
#       --entrypoint bash IMAGE /test.sh
set -uo pipefail

# Uses the image's own /repo, which /etc/pacman.conf already points [repo] at.
# Run this in a throwaway container with nothing mounted there.
REPO_DIR="${REPO_DIR:-/repo}"
REPO_NAME="${REPO_NAME:-repo}"
export REPO_DIR REPO_NAME
export AURDEST=/tmp/test-aurdest

failures=0

ok()   { echo "  PASS: $*"; }
fail() { echo "  FAIL: $*"; failures=$((failures + 1)); }

check_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        ok "$desc"
    else
        fail "$desc (expected '${expected}', got '${actual}')"
    fi
}

# A package file pacman will accept in a repo db: .PKGINFO is enough for
# repo-add to record name, version and depends, which is all the check reads.
make_pkg() {
    local name="$1" ver="$2" dep="$3" tmp
    tmp=$(mktemp -d)
    printf 'pkgname = %s\npkgbase = %s\npkgver = %s\npkgdesc = test fixture\nurl = http://example.invalid\nbuilddate = 0\npackager = test\nsize = 0\narch = x86_64\ndepend = %s\n' \
        "$name" "$name" "$ver" "$dep" > "$tmp/.PKGINFO"
    ( cd "$tmp" && bsdtar -czf "${REPO_DIR}/${name}-${ver}-x86_64.pkg.tar.gz" .PKGINFO )
    rm -rf "$tmp"
}

echo "=== setup ==="
mkdir -p "$REPO_DIR" "$AURDEST"
rm -rf "${REPO_DIR:?}"/* "${AURDEST:?}"/*

# [repo] is listed first in pacman.conf, and pacman -Sy aborts the whole sync if
# its database is missing - leaving the image's build-time databases in place and
# every soname test answering against a stale snapshot. Initialise it first.
repo-add "${REPO_DIR}/${REPO_NAME}.db.tar.gz" >/dev/null 2>&1
if ! sudo pacman -Sy --noconfirm >/dev/null 2>&1; then
    echo "pacman -Sy failed; databases would be stale, cannot test sonames"
    exit 1
fi

# A soname that no longer exists anywhere, and one that currently does. Read the
# live one out of the databases so the fixture cannot rot as Arch moves on.
DEAD_DEP='libbluray.so=3-64'
LIVE_DEP=$(expac -S '%P' extra/libbluray 2>/dev/null | tr ' ' '\n' | grep -m1 '^libbluray\.so=')
if [ -z "$LIVE_DEP" ]; then
    echo "could not determine a live soname to test against"
    exit 1
fi
if [ "$LIVE_DEP" = "$DEAD_DEP" ]; then
    echo "SKIP: ${DEAD_DEP} is live again, fixture needs updating"
    exit 0
fi
echo "  dead dep: ${DEAD_DEP}"
echo "  live dep: ${LIVE_DEP}"

make_pkg fixture-stale 1.0-1 "$DEAD_DEP"
make_pkg fixture-ok 1.0-1 "$LIVE_DEP"
make_pkg fixture-rebuilt 2.0-1.1 "$DEAD_DEP"
repo-add "${REPO_DIR}/${REPO_NAME}.db.tar.gz" "${REPO_DIR}"/*.pkg.tar.gz >/dev/null 2>&1
sudo pacman -Sy --noconfirm >/dev/null 2>&1

fixture_count=$(pacman -Sl "$REPO_NAME" 2>/dev/null | wc -l)
if [ "$fixture_count" -ne 3 ]; then
    echo "fixture repo did not load (${fixture_count} packages, expected 3)"
    exit 1
fi

AUR_BUILDER_LIB_ONLY=1 source /build.sh

echo "=== bump_pkgrel ==="
check_eq "plain pkgrel gets a suffix"    "1.1"   "$(bump_pkgrel 2:9.0.1-1)"
check_eq "suffixed pkgrel increments"    "1.2"   "$(bump_pkgrel 1.0-1.1)"
check_eq "increment is numeric not text" "2.10"  "$(bump_pkgrel 1.0-2.9)"
check_eq "unexpected form still bumps"   "1.1.1.1" "$(bump_pkgrel 1.0-1.1.1)"

# Every bump must sort above the version it replaces, or clients never upgrade.
for pair in "1.1:1" "1.2:1.1" "2.10:2.9"; do
    new="${pair%%:*}" old="${pair##*:}"
    if [ "$(vercmp "1.0-${new}" "1.0-${old}")" = "1" ]; then
        ok "1.0-${new} sorts above 1.0-${old}"
    else
        fail "1.0-${new} does not sort above 1.0-${old}"
    fi
done

# A later genuine AUR release must still win over a locally bumped rebuild.
if [ "$(vercmp '1.0-2' '1.0-1.1')" = "1" ]; then
    ok "genuine AUR bump outranks a local rebuild"
else
    fail "local rebuild outranks a genuine AUR bump"
fi

echo "=== detect_stale_packages ==="
detected=$(detect_stale_packages 2>/dev/null | cut -f1 | sort | tr '\n' ' ')
check_eq "flags only packages with dead deps" "fixture-rebuilt fixture-stale " "$detected"

excluded=$(STALE_EXCLUDE="fixture-stale" detect_stale_packages 2>/dev/null | cut -f1 | sort | tr '\n' ' ')
check_eq "STALE_EXCLUDE skips the named package" "fixture-rebuilt " "$excluded"

version=$(detect_stale_packages 2>/dev/null | grep '^fixture-rebuilt' | cut -f2)
check_eq "reports the repo version, for the bump" "2.0-1.1" "$version"

echo "=== rebuild_stale_packages (aur stubbed) ==="
mkdir -p /tmp/stub
cat > /tmp/stub/aur <<'STUB'
#!/bin/bash
case "$1" in
  fetch)
    base="${!#}"; d="$AURDEST/$base"
    if [ ! -d "$d" ]; then
        mkdir -p "$d"
        printf 'pkgname=%s\npkgver=1.0\npkgrel=1\narch=(x86_64)\n' "$base" > "$d/PKGBUILD"
        git -C "$d" init -q && git -C "$d" add PKGBUILD
        git -C "$d" -c user.email=t@t -c user.name=t commit -qm init
    else
        git -C "$d" checkout -q -- PKGBUILD
    fi ;;
  build)
    echo "BUILD_ARGS=${*:2}" >> /tmp/stub/calls
    grep '^pkgrel=' PKGBUILD >> /tmp/stub/calls ;;
esac
STUB
chmod +x /tmp/stub/aur
export PATH=/tmp/stub:$PATH
: > /tmp/stub/calls

USE_CHROOT=1 SKIP_PGP_CHECK=1 rebuild_stale_packages >/dev/null 2>&1

if grep -q 'pkgrel=1.1' /tmp/stub/calls && grep -q 'pkgrel=1.2' /tmp/stub/calls; then
    ok "builds see a bumped pkgrel derived from the repo version"
else
    fail "pkgrel not bumped as expected: $(tr '\n' ' ' < /tmp/stub/calls)"
fi

if grep -q -- '--chroot' /tmp/stub/calls; then
    ok "USE_CHROOT=1 passes --chroot to aur build"
else
    fail "--chroot missing from aur build args"
fi

# aur sync passes --syncdeps by default; aur build on its own does not, and
# without it makepkg cannot install build deps and every rebuild fails.
if grep -q -- '--syncdeps' /tmp/stub/calls; then
    ok "aur build is given --syncdeps"
else
    fail "--syncdeps missing from aur build args"
fi

if grep -q -- '--makepkg-args --skippgpcheck' /tmp/stub/calls; then
    ok "SKIP_PGP_CHECK=1 passes --skippgpcheck through"
else
    fail "--skippgpcheck missing from aur build args"
fi

# A patched PKGBUILD left behind would be applied twice on the next run.
dirty=0
for d in "$AURDEST"/*/; do
    [ -d "$d/.git" ] || continue
    [ -n "$(git -C "$d" status --porcelain)" ] && dirty=1
done
check_eq "PKGBUILDs restored after the rebuild" "0" "$dirty"

: > /tmp/stub/calls
USE_CHROOT=0 rebuild_stale_packages >/dev/null 2>&1
if grep -q -- '--chroot' /tmp/stub/calls; then
    fail "USE_CHROOT=0 still passed --chroot"
else
    ok "USE_CHROOT=0 omits --chroot"
fi

# The bump is derived from the repo, not the working tree, so a second run with
# an unchanged repo produces the same version rather than climbing each time.
if grep -q 'pkgrel=1.1' /tmp/stub/calls; then
    ok "repeat run reuses the same bump"
else
    fail "repeat run changed the bump: $(tr '\n' ' ' < /tmp/stub/calls)"
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "all stale-dependency tests passed"
    exit 0
fi
echo "${failures} test(s) failed"
exit 1
