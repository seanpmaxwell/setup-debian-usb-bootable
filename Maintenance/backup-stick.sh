#!/bin/bash
# backup-stick.sh - back up the whole encrypted Debian Live stick to a folder.
#
# Run it from the INSTALLER stick (not from the stick being backed up), with
# the Debian Live stick and the (unlocked, mounted) backup drive plugged in:
#
#   sudo bash backup-stick.sh /dev/sdX /media/user/stickbackups
#
# Creates  <folder>/stick-backup-YYYYMMDD-HHMM/  containing:
#   partition-table.sfdisk   the stick's partition layout
#   efi.pcl.zst              EFI partition (boot loader + menu)
#   live.pcl.zst             LIVE partition (Debian base, kernel, boot images)
#   luks-header.img          the encryption header (unlocks with your passphrase)
#   persistence.pcl.zst      your saved system - UNENCRYPTED inside, so keep
#                            this folder on an encrypted drive
#   SHA256SUMS, info.txt
set -eo pipefail

fail() { echo -e "\n❌ $*"; exit 1; }
cleanup() { cryptsetup close stickbackup 2>/dev/null || true; }
trap cleanup EXIT

# --- Arguments and basic checks ---
[ "$EUID" -eq 0 ] || fail "Run with: sudo bash $0 /dev/sdX /path/to/backup/folder"
[ $# -eq 2 ] || fail "Usage: sudo bash $0 /dev/sdX /path/to/backup/folder"
DEV=$1 ; DEST=$2
[[ "$DEV" =~ ^/dev/sd[a-z]$ ]] || fail "$DEV doesn't look like a whole USB disk (expected something like /dev/sdb)."
[ -b "$DEV" ] || fail "$DEV doesn't exist. Check with: lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL"
[ -d "$DEST" ] || fail "Backup folder $DEST doesn't exist. Is the backup drive unlocked and mounted?"
P1=${DEV}1 ; P2=${DEV}2 ; P3=${DEV}3
NAME=$(basename "$DEV")

# Refuse if DEV is the stick we're running from, or holds the backup folder.
on_dev() { local src anc; src=$(findmnt -no SOURCE "$@" 2>/dev/null) || return 1; anc=$(lsblk -snlo NAME "$src" 2>/dev/null) || return 1; grep -qx "$NAME" <<< "$anc"; }
on_dev /run/live/medium && fail "$DEV is the stick this system is running from. Boot the INSTALLER stick and run this from there."
on_dev -T "$DEST" && fail "The backup folder is on $DEV itself. Choose a folder on the backup drive."

# Check it really is the Debian Live stick.
[ "$(blkid -s TYPE -o value "$P1")" = vfat ] && [ "$(blkid -s LABEL -o value "$P1")" = EFI ] || fail "$P1 isn't the FAT partition labelled EFI. Wrong device?"
[ "$(blkid -s TYPE -o value "$P2")" = ext4 ] && [ "$(blkid -s LABEL -o value "$P2")" = LIVE ] || fail "$P2 isn't the ext4 partition labelled LIVE. Wrong device?"
[ "$(blkid -s TYPE -o value "$P3")" = crypto_LUKS ] || fail "$P3 isn't an encrypted (LUKS) partition. Wrong device?"

echo "This stick will be backed up (nothing on it is erased):"
lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$DEV"
echo "Backup folder: $DEST"
read -rp "Type YES to continue: " a ; [ "$a" = YES ] || fail "Cancelled."

# --- Release anything the desktop mounted or unlocked from the stick ---
for p in $(lsblk -lnpo NAME "$DEV" | tac); do umount "$p" 2>/dev/null || true; done
for m in $(lsblk -lnpo NAME,TYPE "$P3" | awk '$2=="crypt"{print $1}'); do cryptsetup close "$m" 2>/dev/null || true; done
MOUNTED=$(lsblk -lno MOUNTPOINTS "$DEV" | tr -d '[:space:]')
[ -z "$MOUNTED" ] || fail "Something on $DEV is still mounted. Close any windows using it and try again."

# --- Tools (the installer stick forgets them at every boot) ---
if ! command -v partclone.vfat >/dev/null || ! command -v partclone.ext4 >/dev/null || ! command -v zstd >/dev/null; then
    echo -e "\n📦 Installing partclone and zstd (needs internet)..."
    grep -rqs 'deb.debian.org' /etc/apt/sources.list /etc/apt/sources.list.d/ || \
        echo 'deb http://deb.debian.org/debian trixie main' > /etc/apt/sources.list.d/backup-tools.list
    apt-get update -qq && apt-get install -y -qq partclone zstd || fail "Couldn't install partclone and zstd. Connect to the internet and try again."
fi

OUT="$DEST/stick-backup-$(date +%Y%m%d-%H%M)"
mkdir -p "$OUT"

echo -e "\n1/5 Saving the partition layout..."
sfdisk -d "$DEV" > "$OUT/partition-table.sfdisk"

echo -e "\n2/5 Backing up the EFI partition..."
partclone.vfat -c -s "$P1" -o - | zstd -T0 -q > "$OUT/efi.pcl.zst"

echo -e "\n3/5 Backing up the LIVE partition (a few minutes)..."
partclone.ext4 -c -s "$P2" -o - | zstd -T0 -q > "$OUT/live.pcl.zst"

echo -e "\n4/5 Backing up the encrypted partition..."
cryptsetup luksHeaderBackup "$P3" --header-backup-file "$OUT/luks-header.img"
chmod 600 "$OUT/luks-header.img"
echo "Enter the stick's encryption passphrase:"
cryptsetup open "$P3" stickbackup
# Finish any writes left over from the last session so the copy is clean.
rc=0 ; e2fsck -p /dev/mapper/stickbackup || rc=$?
[ "$rc" -lt 4 ] || fail "The saved-data filesystem has errors e2fsck couldn't fix (code $rc). Don't rely on this stick; get help."
FREE=$(df --output=avail -B1 "$OUT" | tail -1)
NEED=$(dumpe2fs -h /dev/mapper/stickbackup 2>/dev/null | awk -F: '/^Block count/{c=$2}/^Free blocks/{f=$2}/^Block size/{b=$2}END{printf "%.0f", (c-f)*b}')
[ "$FREE" -gt "$NEED" ] || fail "Not enough space on the backup drive: need about $((NEED/1000000000)) GB, have $((FREE/1000000000)) GB."
partclone.ext4 -c -s /dev/mapper/stickbackup -o - | zstd -T0 -q > "$OUT/persistence.pcl.zst"
cryptsetup close stickbackup

echo -e "\n5/5 Verifying the backup..."
for f in efi live persistence; do
    zstd -dc "$OUT/$f.pcl.zst" | partclone.chkimg -s - > /dev/null 2>&1 || fail "$f.pcl.zst failed verification. Don't rely on this backup."
    echo "  $f: OK"
done
{ echo "Backup of $DEV made $(date)"; lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL,UUID "$DEV"; } > "$OUT/info.txt"
( cd "$OUT" && sha256sum -- * > SHA256SUMS )
sync

echo -e "\n✅ Backup complete: $OUT"
du -sh "$OUT"
echo "The encryption passphrase that unlocks this backup is the one the stick had today."
