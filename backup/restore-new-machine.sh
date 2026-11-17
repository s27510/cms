set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/shop}"
REMOTE="${REMOTE:-gdrive:OpenCart-Backups}"
LOCAL_DIR="${LOCAL_DIR:-$HOME/shop-backups}"
SOURCE="${1:-}"

log()  { echo -e "\n==> $*"; }
fail() { echo -e "\nERROR: $*" >&2; exit 1; }
trap 'fail "stopped at line $LINENO"' ERR

[ -f "$PROJECT_DIR/docker-compose.yml" ] && \
  fail "$PROJECT_DIR already contains a project. Move it away first, or use restore.sh on an existing setup."

log "Checking required tools"
if ! command -v curl >/dev/null || ! command -v unzip >/dev/null; then
  sudo apt-get update -qq && sudo apt-get install -y -qq curl unzip
fi
if ! command -v docker >/dev/null; then
  log "Installing Docker"
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
fi
if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi
compose() { "${DOCKER[@]}" compose "$@"; }

mkdir -p "$LOCAL_DIR"
if [ -n "$SOURCE" ] && [ -f "$SOURCE" ]; then
  ARCHIVE="$(realpath "$SOURCE")"
else
  if ! command -v rclone >/dev/null; then
    log "Installing rclone"
    sudo -v && curl -fsSL https://rclone.org/install.sh | sudo bash
  fi
  REMOTE_NAME="${REMOTE%%:*}"
  if ! rclone listremotes | grep -qx "$REMOTE_NAME:"; then
    log "Connecting Google Drive - a browser window will open, log in with the account that holds the backups"
    rclone config create "$REMOTE_NAME" drive scope=drive.file
  fi
  if [ -z "$SOURCE" ]; then
    SOURCE="$(rclone lsf "$REMOTE" --include 'opencart-backup_*.tar' | sort | tail -n 1)"
    [ -n "$SOURCE" ] || fail "no backups found in $REMOTE"
  fi
  log "Downloading $SOURCE from $REMOTE"
  rclone copy "$REMOTE/$SOURCE" "$LOCAL_DIR" --retries 5
  ARCHIVE="$LOCAL_DIR/$SOURCE"
  [ -f "$ARCHIVE" ] || fail "download failed: $SOURCE"
fi
log "Using backup: $ARCHIVE"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tar -xf "$ARCHIVE" -C "$WORK"
for f in database.sql.gz files.tar.gz project.tar.gz; do
  [ -f "$WORK/$f" ] || fail "backup is missing $f"
done


log "Recreating $PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
tar -xzf "$WORK/project.tar.gz" -C "$PROJECT_DIR"
cd "$PROJECT_DIR"

mapfile -t MOUNTS < <(grep -oE '^\s*-\s*\./[^:]+:/var/www' docker-compose.yml | sed -E 's/^\s*-\s*\.\/([^:]+):.*/\1/')
for d in "${MOUNTS[@]}"; do mkdir -p "$d"; done
[ "${#MOUNTS[@]}" -gt 0 ] && sudo chown -R 33:33 "${MOUNTS[@]}"


log "Building and starting containers (first time takes a few minutes)"
compose up -d --build

log "Waiting for the database"
ready=0
for _ in $(seq 60); do
  if compose exec -T db sh -c 'mariadb -h 127.0.0.1 -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SELECT 1"' >/dev/null 2>&1; then
    ready=1; break
  fi
  sleep 3
done
[ "$ready" = 1 ] || fail "database did not start - check: docker compose logs db"

log "Restoring database"
zcat "$WORK/database.sql.gz" | compose exec -T db sh -c \
  'exec mariadb -h 127.0.0.1 -uroot -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"'

log "Restoring files"
compose exec -T web tar -xzf - -C / < "$WORK/files.tar.gz"

code="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/ || true)"
log "Restore complete (local check: http://localhost:8080 answered $code)"

if [ -x "$PROJECT_DIR/backup/install.sh" ]; then
  if [ "${DOCKER[0]}" = docker ]; then
    read -r -p "Turn on daily backups on this computer now? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] && "$PROJECT_DIR/backup/install.sh"
  else
    echo "Docker was just installed: log out and back in, then run $PROJECT_DIR/backup/install.sh to turn on daily backups."
  fi
fi

cat <<EOF

Last step - point your domain to this computer:
  Cloudflare dashboard -> Zero Trust -> Networks -> Tunnels -> your tunnel -> copy the Linux
  connector install command and run it here. Keep the route as http://localhost:8080.
  Stop the connector on the old computer if it is still running.
EOF
