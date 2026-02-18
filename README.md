# simple-send

Bash script that uploads a file (or a tar.gz'd directory) to Google Drive using
[rclone](https://rclone.org). It downloads rclone into `/tmp`, runs the
authorization flow, uploads the payload, and cleans everything up afterwards.

## Features

- **File mode** – upload a single file as-is.
- **Directory mode** – compress the directory into a `.tar.gz` archive, then upload.
- Installs rclone to a temporary directory (no root required, nothing left behind).
- Interactive Google Drive authorization on first run.
- All temp files (archive, rclone binary, config) are deleted on exit.

## Quick start — run directly from GitHub

One-liner interactive (prompts for path):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Forever-Young/simple-send/main/simple-send.sh)
```

One-liner with parameters (after `--`):

```bash
curl -fsSL https://raw.githubusercontent.com/Forever-Young/simple-send/main/simple-send.sh | bash -s -- --dir /path/to/folder
```

Download and run interactively (will prompt for the path):

```bash
curl -fsSL -o simple-send.sh https://raw.githubusercontent.com/Forever-Young/simple-send/main/simple-send.sh
chmod +x simple-send.sh
./simple-send.sh
```

Or pass parameters directly:

```bash
./simple-send.sh --dir /path/to/folder
./simple-send.sh --file /var/backups/db.sql.gz
```

## Usage

```
Usage: simple-send.sh [OPTIONS]

Upload a file or directory archive to Google Drive via rclone.

Options:
  -f, --file <path>        File to upload
  -d, --dir <path>         Directory to tar.gz and upload
  -r, --remote-dir <name>  Google Drive destination folder  (default: backups)
  -n, --remote-name <name> rclone remote name               (default: gdrive)
      --keep-rclone        Keep rclone for future runs (~/.local/share/gdrive-backup)
      --remove-rclone      Remove previously kept rclone and exit
      --no-cleanup         Keep temporary files after upload
  -h, --help               Show this help message

If neither --file nor --dir is provided, you will be prompted interactively.
```

## Examples

```bash
# Interactive mode — the script will ask what to upload
./simple-send.sh

# Upload a single database dump
./simple-send.sh --file /var/backups/db.sql.gz

# Archive and upload an entire directory to a custom Drive folder
./simple-send.sh --dir /var/www/mysite --remote-dir "server-backups/2024-01"

# Keep rclone installed for faster future runs
./simple-send.sh --file backup.sql.gz --keep-rclone

# Remove the cached rclone when no longer needed
./simple-send.sh --remove-rclone
```

## Requirements

- Linux (x86_64, arm64, or armv7l)
- `bash`, `curl`, `tar`, `unzip` (standard on most distros)
- A Google account for Drive authorization
