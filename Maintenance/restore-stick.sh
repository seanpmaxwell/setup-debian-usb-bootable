#!/bin/bash
# restore-stick.sh - put a backup made by backup-stick.sh back onto a USB stick.
#
# Run it from the INSTALLER stick, with the target stick and the (unlocked,
# mounted) backup drive plugged in:
#
#   sudo bash restore-stick.sh /media/user/stickbackups/stick-backup-YYYYMMDD-HHMM /dev/sdX
#
# EVERYTHING on /dev/sdX is replaced by the backup. The target can be the same
# stick or a new one of the same size or larger. Afterwards the stick unlocks
# with the passphrase it had when the backup was made.
set -eo pipefail

fail() { echo -e "\n❌ $*"; exit 1; }
cleanup() { cryptsetup close stickrestore 2>/dev/null || true; }
trap cleanup EXIT

# --- Arguments and basic checks ---
[ "$EUID" -eq 0 ] || fail "Run with: sudo bash $0 /path/to/stick-backup-folder /dev/sdX"
[ $# -eq 2 ] || fail "Usage: sudo bash $0 /path/to/stick-backup-folder /dev/sdX"
SRC=$1 ; DEV=$2
[[ "$DEV" =~ ^/dev/sd[a-z]$ ]] || fail "$DEV doesn't look like a whole USB disk (expected something like /dev/sdb)."
[ -b "$DEV" ] || fail "$DEV doesn't exist. Check with: lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL"
for f in partition-table.sfdisk efi.pcl.zst live.pcl.zst luks-header.img persistence.pcl.zst SHA256SUMS; do
    [ -s "$SRC/$f" ] || fail "$SRC/$f is missing. Is that a stick-backup-… folder?"
done
P1=${DEV}1 ; P2=${DEV}2 ; P3=${DEV}3
NAME=$(basename "$DEV")

on_dev() { local src anc; src=$(findmnt -no SOURCE "$@" 2>/dev/null) || return 1; anc=$(lsblk -snlo NAME "$src" 2>/dev/null) || return 1; grep -qx "$NAME" <<< "$anc"; }
on_dev /run/live/medium && fail "$DEV is the stick this system is running from. Boot the INSTALLER stick and run this from there."
on_dev -T "$SRC" && fail "The backup is on $DEV itself."

echo "Checking the backup files..."
( cd "$SRC" && sha256sum --quiet -c SHA256SUMS ) || fail "The backup files are damaged or incomplete. Nothing was changed."

echo -e "\nBackup: $SRC"
sed -n 1p "$SRC/info.txt" 2>/dev/null || true
echo -e "\n⚠️  EVERYTHING on this device will be ERASED and replaced:"
lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$DEV"
read -rp "Type ERASE to continue: " a ; [ "$a" = ERASE ] || fail "Cancelled. Nothing was changed."

# --- Tools (the installer stick forgets them at every boot) ---
if ! command -v partclone.vfat >/dev/null || ! command -v partclone.ext4 >/dev/null || ! command -v zstd >/dev/null; then
    echo -e "\n📦 Installing partclone and zstd (needs internet)..."
    grep -rqs 'deb.debian.org' /etc/apt/sources.list /etc/apt/sources.list.d/ || \
        echo 'deb http://deb.debian.org/debian trixie main' > /etc/apt/sources.list.d/backup-tools.list
    apt-get update -qq && apt-get install -y -qq partclone zstd || fail "Couldn't install partclone and zstd. Connect to the internet and try again. Nothing was changed."
fi

# --- Release anything the desktop mounted or unlocked ---
for p in $(lsblk -lnpo NAME "$DEV" | tac); do umount "$p" 2>/dev/null || true; done
for m in $(lsblk -lnpo NAME,TYPE "$DEV" | awk '$2=="crypt"{print $1}'); do cryptsetup close "$m" 2>/dev/null || true; done
MOUNTED=$(lsblk -lno MOUNTPOINTS "$DEV" | tr -d '[:space:]')
[ -z "$MOUNTED" ] || fail "Something on $DEV is still mounted. Close any windows using it and try again. Nothing was changed."

echo -e "\n1/4 Recreating the partitions..."
grep -vE '^(device|last-lba):' "$SRC/partition-table.sfdisk" | sfdisk --wipe always --wipe-partitions always "$DEV" \
    || fail "Couldn't write the partitions (is $DEV smaller than the original stick?)."
partprobe "$DEV" 2>/dev/null || true ; udevadm settle ; sleep 2
[ -b "$P3" ] || fail "The new partitions didn't appear. Unplug and replug $DEV, then run this again."

echo -e "\n2/4 Restoring the EFI partition..."
zstd -dc "$SRC/efi.pcl.zst" | partclone.vfat -r -s - -o "$P1"

echo -e "\n3/4 Restoring the LIVE partition (a few minutes)..."
zstd -dc "$SRC/live.pcl.zst" | partclone.ext4 -r -s - -o "$P2"

echo -e "\n4/4 Restoring the encrypted partition..."
cryptsetup -q luksHeaderRestore "$P3" --header-backup-file "$SRC/luks-header.img"
echo "Enter the encryption passphrase the stick had when this backup was made:"
cryptsetup open "$P3" stickrestore
zstd -dc "$SRC/persistence.pcl.zst" | partclone.ext4 -r -s - -o /dev/mapper/stickrestore
cryptsetup close stickrestore
sync

echo -e "\n✅ Restore complete. Shut down, unplug the installer stick, and boot the restored stick."
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEV"
