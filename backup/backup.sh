#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/shop}"
REMOTE="${REMOTE:-gdrive:OpenCart-Backups}"
LOCAL_DIR="${LOCAL_DIR:-$HOME/shop-backups}"
KEEP_LOCAL_DAYS="${KEEP_LOCAL_DAYS:-7}"
KEEP_REMOTE_DAYS="${KEEP_REMOTE_DAYS:-30}"

log() { echo "[$(date '+%F %T')] $*"; }
fail() { log "ERROR: $*"; exit 1; }
trap 'fail "backup failed at line $LINENO"' ERR

mkdir -p "$LOCAL_DIR"
exec 9>"$LOCAL_DIR/.lock"
flock -n 9 || { log "Another backup is already running, skipping."; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$PROJECT_DIR" || fail "project folder $PROJECT_DIR not found"
command -v rclone >/dev/null || fail "rclone is not installed"
[ -n "$(docker compose ps --status running -q db)" ]  || fail "database container is not running"
[ -n "$(docker compose ps --status running -q web)" ] || fail "web container is not running"

log "Dumping database"
docker compose exec -T db sh -c \
  'exec mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction --quick --routines --triggers "$MARIADB_DATABASE"' \
  | gzip > "$WORK/database.sql.gz"
zcat "$WORK/database.sql.gz" | tail -n 1 | grep -q 'Dump completed' || fail "database dump is incomplete"

STORAGE_DIR="$(docker compose exec -T web php -r 'require "/var/www/html/config.php"; echo rtrim(DIR_STORAGE, "/");')"
PATHS=(var/www/html)
case "$STORAGE_DIR" in
  /var/www/html/*) ;;
  /*) PATHS+=("${STORAGE_DIR#/}") ;;
  *) fail "could not read DIR_STORAGE from config.php" ;;
esac
log "Archiving files: ${PATHS[*]}"
rc=0
docker compose exec -T web tar -czf - -C / \
  --exclude="${STORAGE_DIR#/}/cache/*" \
  --exclude="${STORAGE_DIR#/}/session/*" \
  "${PATHS[@]}" > "$WORK/files.tar.gz" || rc=$?
[ "$rc" -le 1 ] || fail "file archive failed (tar exit code $rc)"

log "Archiving project configuration"
tar -czf "$WORK/project.tar.gz" --ignore-failed-read \
  --exclude=./opencart --exclude=./storage -C "$PROJECT_DIR" .

NAME="opencart-backup_$(date +%F_%H%M).tar"
tar -cf "$LOCAL_DIR/$NAME" -C "$WORK" database.sql.gz files.tar.gz project.tar.gz
log "Created $NAME ($(du -h "$LOCAL_DIR/$NAME" | cut -f1))"

log "Waiting for network"
for _ in $(seq 30); do getent hosts www.googleapis.com >/dev/null && break; sleep 10; done

log "Uploading to $REMOTE"
rclone copy "$LOCAL_DIR/$NAME" "$REMOTE" --retries 5
rclone delete "$REMOTE" --min-age "${KEEP_REMOTE_DAYS}d" --include 'opencart-backup_*.tar' --drive-use-trash=false
find "$LOCAL_DIR" -maxdepth 1 -name 'opencart-backup_*.tar' -mtime +"$KEEP_LOCAL_DAYS" -delete

log "Backup finished: $NAME"
