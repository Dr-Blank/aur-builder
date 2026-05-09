# aur-builder

Self-hosted AUR package builder. Arch Linux container that takes a list of AUR package names, builds them using [aurutils](https://github.com/AladW/aurutils) with a devtools clean chroot, and outputs a ready-to-use pacman repository to a mounted volume.

Think local [chaotic-aur](https://aur.chaotic.cx/) — you control which packages get built.

## Quick Start

```bash
# 1. List the AUR packages you want
echo "paru" >> packages.txt
echo "yay" >> packages.txt

# 2. Build packages
docker compose up --build

# Packages land in ./repo/
```

> **Note:** Requires `privileged: true` — devtools uses `systemd-nspawn` for clean chroot builds.

## Configuration

| Variable | Default | Description |
|---|---|---|
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
| `aur-chroot:/var/lib/aurbuild` | *Optional.* Persists build chroot (~500 MB) — speeds up subsequent runs. |

## Use Pre-built Image

```yaml
# docker-compose.yml
services:
  aur-builder:
    image: ghcr.io/dr-blank/aur_builder:latest
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

### Scheduled builds (ofelia)

```bash
docker compose -f docker-compose.yml \
               -f docker-compose.serve.yml \
               -f docker-compose.cron.yml up -d
```

Default schedule: every 6 hours. Edit `ofelia.job-run.build-aur.schedule` in `docker-compose.cron.yml`.

## Releases

```bash
bash scripts/release.sh 1.0.0
```

Tags `v1.0.0`, pushes to GitHub — Actions builds and pushes image to ghcr.io automatically.

VSCode: `Ctrl+Shift+B` → **Release: Tag and push new version**.
