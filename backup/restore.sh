#!/usr/bin/env bash
set -Eeuo pipefail

ARCHIVE="${1:?Usage: $0 <opencart-backup_*.tar>}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/shop}"
ARCHIVE="$(realpath "$ARCHIVE")"

read -r -p "This overwrites the current database and files in $PROJECT_DIR. Type YES to continue: " ok
[ "$ok" = "YES" ] || { echo "Cancelled."; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tar -xf "$ARCHIVE" -C "$WORK"
cd "$PROJECT_DIR"

echo "Restoring database..."
zcat "$WORK/database.sql.gz" | docker compose exec -T db sh -c \
  'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"'

echo "Restoring files..."
docker compose exec -T web tar -xzf - -C / < "$WORK/files.tar.gz"

echo "Done. project.tar.gz (compose file, Dockerfile, .env) was not applied automatically;"
echo "it is in the archive if you need it:  tar -xf $ARCHIVE project.tar.gz"
