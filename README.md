# aur-builder

Self-hosted AUR package builder. Arch Linux container that takes a list of AUR package names, builds them using [aurutils](https://github.com/AladW/aurutils) with a devtools clean chroot, and outputs a ready-to-use pacman repository to a mounted volume.

Think self hosted [chaotic-aur](https://aur.chaotic.cx/).

## Quick Start

```bash
# 1. List the AUR packages you want in packages.txt or set PACKAGES env var
echo "paru" >> packages.txt
echo "yay" >> packages.txt

# 2. Build packages
docker compose up --build

# Packages land in ./repo/
```

> **Note:** Requires `privileged: true` as devtools uses `systemd-nspawn` for clean chroot builds.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `CRON` | `"0 2 * * *"` | Cron schedule(s) for automatic builds. Use `\|` to separate multiple. Empty = one-shot. |
| `PACKAGES` | `""` | Space-separated package names (merged with packages.txt) |
| `PACKAGES_FILE` | `/packages.txt` | Path to package list inside container |
| `REPO_NAME` | `repo` | Pacman repo/db name |
| `REPO_DIR` | `/repo` | Repo output path inside container |
| `CHECK_STALE_DEPS` | `1` | Rebuild packages broken by dependency soname bumps. `0` disables. |
| `STALE_EXCLUDE` | `""` | Space-separated packages never auto-rebuilt by that check. |

`packages.txt` supports blank lines and `#` comments.

## Stale dependency rebuilds

`aur sync` decides what to build by comparing versions, so it never notices when a
dependency's soname changes underneath a package. Arch moves `libbluray.so.3` to
`libbluray.so.4`, the AUR `pkgver` does not change, and the package sitting in your
repo keeps linking against a soname nothing provides:

```
warning: cannot resolve "libbluray.so=3-64", a dependency of "ffmpeg-libfdk_aac"
```

That package is then uninstallable and unupgradable until it is rebuilt by hand.

On each run, after the normal sync, every package in the repo is checked: do all of
its recorded dependencies still resolve? Anything that fails is rebuilt. The check
costs milliseconds per package, so a rebuild only fires when something is genuinely
broken — a few times a year, not on every run.

Rebuilds also bump `pkgrel` (`9.0.1-1` becomes `9.0.1-1.1`, the same scheme Arch uses
for its own rebuilds). Without that, the rebuilt package carries the version clients
already have installed, so `pacman -Syu` would report nothing to upgrade and leave the
broken copy in place. A later genuine AUR update still takes precedence
(`9.0.1-2` > `9.0.1-1.1`).

## Volumes

| Mount | Purpose |
|---|---|
| `./repo:/repo` | **Required.** Pacman repository output. |
| `./packages.txt:/packages.txt:ro` | Package list input. |
| `aur-chroot:/var/lib/aurbuild` | *Optional.* Persists build chroot and speeds up subsequent runs. |

## Use Pre-built Image

```yaml
# docker-compose.yml
services:
  aur-builder:
    image: ghcr.io/dr-blank/aur_builder:latest  # built automatically on push to main
    privileged: true
    volumes:
      - ./repo:/repo
      - ./packages.txt:/packages.txt:ro
```

## Compose Examples

### Serve repo over HTTP (nginx)

```bash
docker compose -f docker-compose.yml -f docker-compose.serve.yml up
```

Repo served at `http://HOST:8080`. Add to client `/etc/pacman.conf`:

```ini
[repo]
SigLevel = Optional TrustAll
Server = http://YOUR_SERVER:8080
```

### Scheduled builds

Set `CRON` to a cron expression. Default is `0 2 * * *` (daily at 2 AM). Use `|` to run on multiple schedules:

```yaml
environment:
  CRON: "0 2 * * *"               # daily at 2 AM
  CRON: "0 2 * * *|0 14 * * *"   # 2 AM and 2 PM
```

One-shot mode (run once and exit): set `CRON: ""` and use `docker compose run aur-builder`.
