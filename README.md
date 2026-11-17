# Backups

Daily backups of the OpenCart shop (database + files) to Google Drive, plus scripts to restore them.

| Script | What it does |
|---|---|
| `backup.sh` | Makes one backup and uploads it to Google Drive |
| `install.sh` | Runs a first backup now and schedules `backup.sh` daily at 03:00 |
| `restore.sh` | Restores a backup on a machine where the shop is already running |
| `restore-new-machine.sh` | Rebuilds the whole shop on a new computer from a backup |

## What a backup contains

Each run creates one file, `opencart-backup_YYYY-MM-DD_HHMM.tar`, containing:

| Part | Contents |
|---|---|
| `database.sql.gz` | Full MariaDB dump: dishes, categories, settings, customers, orders |
| `files.tar.gz` | OpenCart files: images, theme, installed extensions (incl. `atelier`), storage folder (without cache and sessions) |
| `project.tar.gz` | `docker-compose.yml`, `Dockerfile`, `.env`, these scripts and other project files |

Copies are kept for **7 days** in `~/shop-backups/` and for **30 days** in the Google Drive folder `OpenCart-Backups`. Older ones are deleted automatically.

> The backups contain the `.env` passwords, the admin password hash and customer data. Keep the Drive folder private.

## Requirements

- The shop running with Docker Compose in `~/shop` (containers `web` and `db`)
- Your user in the `docker` group
- **rclone** connected to Google Drive as a remote called `gdrive`
- systemd (Ubuntu and Arch both have it)

## Setup

1. **Install rclone**
   - Arch: `sudo pacman -S rclone`
   - Ubuntu: `sudo -v ; curl https://rclone.org/install.sh | sudo bash`

2. **Connect Google Drive**

   ```bash
   rclone config
   ```

   | Prompt | Answer |
   |---|---|
   | `n/s/q>` | `n` |
   | `name>` | `gdrive` |
   | `Storage>` | `drive` |
   | `client_id>` / `client_secret>` | press Enter |
   | `scope>` | `drive.file` (rclone only sees files it created) |
   | `service_account_file>` | press Enter |
   | `Edit advanced config?` | `n` |
   | `Use web browser to automatically authenticate?` | `y`, then log in and click **Allow** |
   | `Configure this as a Shared Drive?` | `n` |
   | `Keep this "gdrive" remote?` | `y`, then `q` to quit |

   Check it: `rclone mkdir gdrive:OpenCart-Backups && rclone lsd gdrive:`

3. **Install the schedule**

   ```bash
   cd ~/shop/backup
   chmod +x *.sh
   ./install.sh
   ```

   This runs the first backup immediately and prints its log. It then schedules a daily run at 03:00. If the computer is off or asleep at 03:00, the backup runs as soon as it's back on. The script asks for your sudo password once, to keep the schedule running when you're not logged in.

   The schedule points to the scripts' current location. If you move this folder, run `./install.sh` again.

## Everyday use

| Task | Command |
|---|---|
| Run a backup now | `systemctl --user start opencart-backup` |
| See the backup log | `journalctl --user -u opencart-backup -n 30` |
| See the next scheduled run | `systemctl --user list-timers opencart-backup.timer` |
| List backups on Drive | `rclone ls gdrive:OpenCart-Backups` |
| List local backups | `ls -lh ~/shop-backups/` |
| Stop the daily backups | `systemctl --user disable --now opencart-backup.timer` |

## Restore on the same computer

Use this when the shop still runs but data was lost or a change went wrong.

```bash
# backups from the last 7 days are already local; older ones come from Drive:
rclone copy gdrive:OpenCart-Backups/opencart-backup_2026-11-17_0300.tar ~/shop-backups/

cd ~/shop && docker compose up -d
~/shop/backup/restore.sh ~/shop-backups/opencart-backup_2026-11-17_0300.tar
```

The script asks you to type `YES`, then replaces the database and the OpenCart files with the backup's version.

- Anything added after that backup (new orders, new dishes) is lost.
- Files created after the backup are not deleted, only overwritten.
- `project.tar.gz` (Docker setup, `.env`) is **not** applied automatically. Extract it by hand if you need it.

## Restore on a new computer

`restore-new-machine.sh` rebuilds everything from a backup:
1. downloads the backup,
2. recreates `~/shop`,
3. starts the containers,
4. restores the database and files.

It stops without changing anything if `~/shop` already contains a project.

```bash
./restore-new-machine.sh                                           # newest backup on Drive
./restore-new-machine.sh opencart-backup_2026-11-17_0300.tar       # a specific backup on Drive
./restore-new-machine.sh ~/Downloads/opencart-backup_2026-11-17_0300.tar   # a downloaded file
```

**On Ubuntu**, the script installs Docker and rclone itself if they're missing.

**On Arch**, install them first. The script then skips its own install step, which uses `apt`:

```bash
sudo pacman -S --needed docker docker-compose docker-buildx rclone curl unzip
sudo systemctl enable --now docker
sudo usermod -aG docker $USER      # then log out and back in
```

Keep a copy of `restore-new-machine.sh` in Google Drive, so you can reach it without the old computer: `rclone copy ~/shop/backup/restore-new-machine.sh gdrive:OpenCart-Backups`

After restoring:
- **Domain:** in the Cloudflare dashboard, run your tunnel's connector install command on the new computer. Stop the connector on the old one.
- **Daily backups:** run `~/shop/backup/install.sh` on the new computer.

## Settings

The defaults are at the top of the scripts. You can also override them for one run with environment variables, e.g. `KEEP_REMOTE_DAYS=60 ./backup.sh`.

| Variable | Default | Meaning |
|---|---|---|
| `PROJECT_DIR` | `~/shop` | Folder with `docker-compose.yml` |
| `REMOTE` | `gdrive:OpenCart-Backups` | rclone remote and Drive folder |
| `LOCAL_DIR` | `~/shop-backups` | Where local copies are kept |
| `KEEP_LOCAL_DAYS` | `7` | Days to keep local copies |
| `KEEP_REMOTE_DAYS` | `30` | Days to keep copies on Drive |

The 03:00 time is set in `~/.config/systemd/user/opencart-backup.timer` (`OnCalendar=`). After changing it, run `systemctl --user daemon-reload`.

## Troubleshooting

| Message | Fix |
|---|---|
| `database container is not running` / `web container is not running` | `cd ~/shop && docker compose up -d` |
| `rclone is not installed` | Install rclone (Setup, step 1) |
| `didn't find section in config file` | The remote isn't called `gdrive`. Run `rclone config` and check the name |
| `invalid_grant` / token expired | `rclone config reconnect gdrive:` |
| `permission denied ... docker.sock` | `sudo usermod -aG docker $USER`, then log out and back in |
| `database dump is incomplete` | Check the database container: `docker compose logs db` |
| Backup didn't run at night | `journalctl --user -u opencart-backup` and `loginctl show-user $USER -p Linger` (should be `yes`) |
