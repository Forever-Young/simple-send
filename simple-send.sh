#!/usr/bin/env bash
set -euo pipefail

# ── defaults ────────────────────────────────────────────────────────
INPUT_FILE=""
INPUT_DIR=""
REMOTE_DIR=""
DEFAULT_REMOTE_DIR="transfer"
RCLONE_REMOTE_NAME="gdrive"
CLEANUP=true
KEEP_RCLONE=false
REMOVE_RCLONE=false

RCLONE_PERSIST_DIR="${HOME}/.local/share/gdrive-backup"
TMPDIR_BASE="/tmp/gdrive-backup-$$"
RCLONE_BIN=""
ARCHIVE_PATH=""

# ── helpers ─────────────────────────────────────────────────────────
die()  { echo "ERROR: $*" >&2; cleanup; exit 1; }
info() { echo ":: $*"; }

cleanup() {
  if [ "$CLEANUP" = true ] && [ -d "$TMPDIR_BASE" ]; then
    info "Cleaning up temporary files…"
    rm -rf "$TMPDIR_BASE"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage: gdrive-backup.sh [OPTIONS]

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
USAGE
  exit 0
}

# ── parse args ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)        INPUT_FILE="$2";          shift 2 ;;
    -d|--dir)         INPUT_DIR="$2";           shift 2 ;;
    -r|--remote-dir)  REMOTE_DIR="$2";          shift 2 ;;
    -n|--remote-name) RCLONE_REMOTE_NAME="$2";  shift 2 ;;
    --keep-rclone)    KEEP_RCLONE=true;          shift   ;;
    --remove-rclone)  REMOVE_RCLONE=true;        shift   ;;
    --no-cleanup)     CLEANUP=false;            shift   ;;
    -h|--help)        usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

# ── handle --remove-rclone ──────────────────────────────────────────
if [ "$REMOVE_RCLONE" = true ]; then
  if [ -d "$RCLONE_PERSIST_DIR" ]; then
    rm -rf "$RCLONE_PERSIST_DIR"
    info "Removed rclone from $RCLONE_PERSIST_DIR"
  else
    info "Nothing to remove — $RCLONE_PERSIST_DIR does not exist."
  fi
  exit 0
fi

# ── interactive prompts for missing required input ──────────────────
if [ -z "$INPUT_FILE" ] && [ -z "$INPUT_DIR" ]; then
  # Enable tab completion for file paths in interactive read if available
  if [ -t 0 ]; then
    # Try to use readline if available (standard in many bash builds)
    read -e -rp "Path to a file or directory to upload (Tab for autocomplete): " USER_INPUT
  else
    read -rp "Path to a file or directory to upload: " USER_INPUT
  fi
  [ -z "$USER_INPUT" ] && die "Nothing provided."
  if [ -d "$USER_INPUT" ]; then
    INPUT_DIR="$USER_INPUT"
  elif [ -f "$USER_INPUT" ]; then
    INPUT_FILE="$USER_INPUT"
  else
    die "'$USER_INPUT' is not a valid file or directory."
  fi
fi

# ── prompt for remote dir if not provided ───────────────────────────
if [ -z "$REMOTE_DIR" ]; then
  if [ -t 0 ]; then
    read -e -rp "Google Drive destination folder: " -i "$DEFAULT_REMOTE_DIR" REMOTE_DIR
  else
    REMOTE_DIR="$DEFAULT_REMOTE_DIR"
  fi
fi

if [ -n "$INPUT_FILE" ] && [ -n "$INPUT_DIR" ]; then
  die "Provide either --file or --dir, not both."
fi

# ── validate input ──────────────────────────────────────────────────
if [ -n "$INPUT_DIR" ]; then
  [ -d "$INPUT_DIR" ] || die "Directory not found: $INPUT_DIR"
  INPUT_DIR="$(cd "$INPUT_DIR" && pwd)"  # absolute path
fi
if [ -n "$INPUT_FILE" ]; then
  [ -f "$INPUT_FILE" ] || die "File not found: $INPUT_FILE"
  INPUT_FILE="$(realpath "$INPUT_FILE")"
fi

# ── prepare tmp dir ────────────────────────────────────────────────
mkdir -p "$TMPDIR_BASE"

# ── create archive if directory was given ───────────────────────────
if [ -n "$INPUT_DIR" ]; then
  DIRNAME="$(basename "$INPUT_DIR")"
  ARCHIVE_PATH="$TMPDIR_BASE/${DIRNAME}.tar.gz"
  info "Archiving directory → $ARCHIVE_PATH"
  tar -czf "$ARCHIVE_PATH" -C "$(dirname "$INPUT_DIR")" "$DIRNAME"
  UPLOAD_PATH="$ARCHIVE_PATH"
else
  UPLOAD_PATH="$INPUT_FILE"
fi

UPLOAD_NAME="$(basename "$UPLOAD_PATH")"

# ── install rclone ──────────────────────────────────────────────────
download_rclone() {
  local dest_dir="$1"
  mkdir -p "$dest_dir"
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    armv7l)  arch="arm-v7" ;;
    *) die "Unsupported architecture: $arch" ;;
  esac
  local url="https://downloads.rclone.org/rclone-current-linux-${arch}.zip"
  info "Fetching $url"
  curl -fsSL "$url" -o "$TMPDIR_BASE/rclone.zip"
  unzip -qo "$TMPDIR_BASE/rclone.zip" -d "$dest_dir"
  rm -f "$TMPDIR_BASE/rclone.zip"
}

# Try persistent copy first, then download
if [ -d "$RCLONE_PERSIST_DIR/rclone" ]; then
  RCLONE_BIN="$(find "$RCLONE_PERSIST_DIR/rclone" -name rclone -type f | head -1)"
  if [ -n "$RCLONE_BIN" ] && [ -x "$RCLONE_BIN" ]; then
    info "Using cached rclone → $RCLONE_BIN"
  else
    RCLONE_BIN=""
  fi
fi

if [ -z "$RCLONE_BIN" ]; then
  if [ "$KEEP_RCLONE" = true ]; then
    info "Downloading rclone (will be kept in $RCLONE_PERSIST_DIR)…"
    download_rclone "$RCLONE_PERSIST_DIR/rclone"
    RCLONE_BIN="$(find "$RCLONE_PERSIST_DIR/rclone" -name rclone -type f | head -1)"
  else
    info "Downloading rclone (temporary)…"
    download_rclone "$TMPDIR_BASE/rclone"
    RCLONE_BIN="$(find "$TMPDIR_BASE/rclone" -name rclone -type f | head -1)"
  fi
  [ -x "$RCLONE_BIN" ] || chmod +x "$RCLONE_BIN"
  info "rclone installed → $RCLONE_BIN"
fi

# ── configure rclone for Google Drive ───────────────────────────────
# Use persistent config when rclone lives in the persist dir
if [ "$KEEP_RCLONE" = true ] || [[ "$RCLONE_BIN" == "$RCLONE_PERSIST_DIR"* ]]; then
  RCLONE_CONF="$RCLONE_PERSIST_DIR/rclone.conf"
  mkdir -p "$RCLONE_PERSIST_DIR"
else
  RCLONE_CONF="$TMPDIR_BASE/rclone.conf"
fi
export RCLONE_CONFIG="$RCLONE_CONF"

if ! "$RCLONE_BIN" listremotes 2>/dev/null | grep -q "^${RCLONE_REMOTE_NAME}:$"; then
  info "No remote '$RCLONE_REMOTE_NAME' found – starting configuration."
  
  if [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ]; then
    CURRENT_USER="$(whoami)"
    CURRENT_HOST="$(hostname -f 2>/dev/null || hostname)"
    echo -e "\033[1;33m"
    echo "-----------------------------------------------------------------------"
    echo "REMOTE AUTHENTICATION HINT"
    echo "To authorize, run this command in a NEW terminal on your LOCAL machine:"
    echo ""
    echo "    ssh ${CURRENT_USER}@${CURRENT_HOST} -N -L 53682:127.0.0.1:53682"
    echo ""
    echo "Then continue here. When rclone shows a 127.0.0.1 link, it will work."
    echo "-----------------------------------------------------------------------"
    echo -e "\033[0m"
  fi

  "$RCLONE_BIN" config create "$RCLONE_REMOTE_NAME" drive --config "$RCLONE_CONF"
fi

# Always verify if the token is actually working before proceeding
CHECK_OUTPUT=$("$RCLONE_BIN" lsd "${RCLONE_REMOTE_NAME}:" --config "$RCLONE_CONF" 2>&1 || true)
if [[ "$CHECK_OUTPUT" == *"empty token found"* ]] || [[ "$CHECK_OUTPUT" == *"failed to create oauth client"* ]] || [[ "$CHECK_OUTPUT" == *"invalid_grant"* ]]; then
  info "Token for '$RCLONE_REMOTE_NAME' is missing or invalid."
  
  if [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ]; then
    # Get the current user and host for the suggestion
    CURRENT_USER="$(whoami)"
    CURRENT_HOST="$(hostname -f 2>/dev/null || hostname)"
    
    echo -e "\033[1;33m" # Yellow Bold
    echo "-----------------------------------------------------------------------"
    echo "REMOTE AUTHENTICATION REQUIRED"
    echo "To authorize, run this command in a NEW terminal on your LOCAL machine:"
    echo ""
    echo "    ssh ${CURRENT_USER}@${CURRENT_HOST} -N -L 53682:127.0.0.1:53682"
    echo ""
    echo "After running it, continue here and choose 'y' for 'Use auto config?'"
    echo "-----------------------------------------------------------------------"
    echo -e "\033[0m" # Reset
  fi

  info "Starting re-authorization..."
  "$RCLONE_BIN" config reconnect "${RCLONE_REMOTE_NAME}:" --config "$RCLONE_CONF"
fi

# Always verify if the token is actually working before proceeding
CHECK_OUTPUT=$("$RCLONE_BIN" lsd "${RCLONE_REMOTE_NAME}:" --config "$RCLONE_CONF" 2>&1 || true)
if [[ "$CHECK_OUTPUT" == *"empty token found"* ]] || [[ "$CHECK_OUTPUT" == *"failed to create oauth client"* ]] || [[ "$CHECK_OUTPUT" == *"invalid_grant"* ]]; then
  info "Token for '$RCLONE_REMOTE_NAME' is missing or invalid."
  info "Follow the prompts below. When asked 'Use auto config?', select 'n' (No) for remote/headless setup."
  "$RCLONE_BIN" config reconnect "${RCLONE_REMOTE_NAME}:" \
    --config "$RCLONE_CONF"
fi

# Always verify if the token is actually working before proceeding
CHECK_OUTPUT=$("$RCLONE_BIN" lsd "${RCLONE_REMOTE_NAME}:" --config "$RCLONE_CONF" 2>&1 || true)
if [[ "$CHECK_OUTPUT" == *"empty token found"* ]] || [[ "$CHECK_OUTPUT" == *"failed to create oauth client"* ]]; then
  info "Token for '$RCLONE_REMOTE_NAME' is missing or invalid. Re-authorizing..."
  "$RCLONE_BIN" config reconnect "${RCLONE_REMOTE_NAME}:" \
    --config "$RCLONE_CONF" \
    --rclone-no-auto-config
fi

# ── upload ──────────────────────────────────────────────────────────
info "Uploading '$UPLOAD_NAME' → ${RCLONE_REMOTE_NAME}:${REMOTE_DIR}/"
"$RCLONE_BIN" copyto \
  "$UPLOAD_PATH" \
  "${RCLONE_REMOTE_NAME}:${REMOTE_DIR}/${UPLOAD_NAME}" \
  --config "$RCLONE_CONF" \
  --progress

info "Done! File available at ${RCLONE_REMOTE_NAME}:${REMOTE_DIR}/${UPLOAD_NAME}"
