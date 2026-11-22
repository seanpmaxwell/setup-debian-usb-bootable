#!/bin/bash
# routine-update - safe updates for the encrypted Debian Live USB
set -e

LIVE_INITRD=/run/live/medium/live/initrd.img
BACKUP_INITRD=/run/live/medium/live/initrd.img.good
HELPER=/usr/lib/live/boot/9990-misc-helpers.sh
HELPER_ORIG=/usr/local/share/live-boot-orig/9990-misc-helpers.sh   # dpkg-divert puts each new live-boot version here
MARK='patched: open read-write'
WARN=""

fail() { echo -e "\n❌ $*"; exit 1; }

# --- Safety checks before touching anything ---
[ "$EUID" -eq 0 ] || fail "Run with: sudo $(basename "$0")"
grep -qw persistence-read-only /proc/cmdline && fail "Discard-changes mode: updates would be lost. Reboot into 'Save changes'."
findmnt -no OPTIONS / | grep -q 'upperdir=/run/live/persistence/' || fail "Saved storage isn't in use, so updates would be lost. Reboot into 'Save changes'."
cmp -s "/boot/vmlinuz-$(uname -r)" /run/live/medium/live/vmlinuz || fail "The stick has a different kernel than the one running (after kernel-update?). Reboot into 'Save changes' first."
HOLDS=$(apt-mark showhold)
{ grep -qx "linux-image-$(uname -r)" <<< "$HOLDS" && grep -qx linux-image-amd64 <<< "$HOLDS"; } || fail "Kernel not held. Run: sudo apt-mark hold linux-image-amd64 linux-image-$(uname -r)"
[ -s "$LIVE_INITRD" ] || fail "Boot image $LIVE_INITRD is missing."
{ [ -s "$BACKUP_INITRD" ] && lsinitramfs "$BACKUP_INITRD" >/dev/null 2>&1; } || fail "Backup boot image $BACKUP_INITRD is missing or unreadable. Fix this before updating."

# --- Remove old kernels left by kernel-update (only the running kernel can boot from the stick) ---
OLDK=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'linux-image-[0-9]*' 2>/dev/null | awk '$1 ~ /^[hi]i/ {print $2}' | grep -vx "linux-image-$(uname -r)" || true)
if [ -n "$OLDK" ]; then
    echo -e "\n🗑️  Removing old kernel(s): $OLDK"
    apt-mark unhold $OLDK > /dev/null
    apt-get purge -y $OLDK
    mount -o remount,rw /run/live/medium
    rm -f /run/live/medium/live/vmlinuz[0-9]* /run/live/medium/live/initrd[0-9]*.img /run/live/medium/live/vmlinuz.prev /run/live/medium/live/initrd.img.prev
fi

# --- Updates ---
echo -e "\n🔄 1/5: Fetching package lists...";  apt-get update
echo -e "\n📦 2/5: Upgrading packages...";      apt-get full-upgrade -y
echo -e "\n🧹 3/5: Removing unused packages..."; apt-get autoremove -y
echo -e "\n🧽 4/5: Cleaning package cache...";  apt-get clean

# --- Keep the read-only fix in place if live-boot was updated ---
echo -e "\n🔐 5/5: Checking the boot image..."
TMP=$(mktemp)
sed 's|opts="${opts} --readonly"|: # patched: open read-write so the ext4 journal can be replayed; filesystem is still mounted ro|' "$HELPER_ORIG" > "$TMP"
if ! grep -q "$MARK" "$TMP"; then
    # The new live-boot no longer has the line the fix changes. Keep the current (patched) helper.
    WARN="live-boot was updated and the read-only fix no longer applies to it. The current fix was kept, but get this looked at."
elif ! cmp -s "$TMP" "$HELPER"; then
    echo "live-boot was updated: re-applying the read-only fix and rebuilding..."
    cp "$TMP" "$HELPER"
    update-initramfs -u
fi
rm -f "$TMP"

# --- Verify the boot image the stick actually uses ---
OK=1
CONTENTS=$(lsinitramfs "$LIVE_INITRD") || OK=0
for item in 'sbin/cryptsetup$' 'dm-crypt\.ko' 'scripts/live$'; do
    echo "$CONTENTS" | grep -qE "$item" || { echo "  missing: $item"; OK=0; }
done
TMPD=$(mktemp -d)
if unmkinitramfs "$LIVE_INITRD" "$TMPD" 2>/dev/null && grep -rqs "$MARK" "$TMPD"; then :; else echo "  missing: read-only fix"; OK=0; fi
rm -rf "$TMPD"

if [ "$OK" -ne 1 ]; then
    echo "Restoring the backup boot image..."
    if mount -o remount,rw /run/live/medium \
       && cp "$BACKUP_INITRD" "$LIVE_INITRD.tmp" && mv "$LIVE_INITRD.tmp" "$LIVE_INITRD" && sync \
       && lsinitramfs "$LIVE_INITRD" | grep -q 'sbin/cryptsetup$'; then
        fail "The new boot image failed its checks, so the backup was restored. It's safe to reboot, but get this looked at before the next update."
    else
        fail "The new boot image failed its checks AND restoring the backup failed. DON'T REBOOT - get help first."
    fi
fi
echo "  boot image OK (encryption support + read-only fix)"

# --- Kernel notice ---
INST=$(dpkg-query -W -f='${Version}' linux-image-amd64 2>/dev/null || true)
CAND=$(apt-cache policy linux-image-amd64 | awk '/Candidate:/{print $2}')
if [ -n "$CAND" ] && [ "$INST" != "$CAND" ]; then
    echo -e "\nℹ️  A newer kernel is available (${INST:-none} → $CAND). To install it: make a full backup of the stick, then: sudo kernel-update"
fi

if [ -n "$WARN" ]; then
    echo -e "\n⚠️  $WARN"
    echo "   The boot image passed its checks, so it's safe to reboot."
    exit 1
fi
echo -e "\n✅ Update complete. Safe to reboot."
