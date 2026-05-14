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

`packages.txt` supports blank lines and `#` comments.

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
