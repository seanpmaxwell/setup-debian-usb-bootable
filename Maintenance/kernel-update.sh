#!/bin/bash
# kernel-update - put the newest Debian kernel on the encrypted Debian Live USB.
# Install as /usr/local/sbin/kernel-update and run with:  sudo kernel-update
#
# Make a full backup of the stick first: restoring it is the way back if the
# new kernel doesn't work. The old kernel package is removed by the next run of
# routine-update, after you've rebooted into the new kernel.
set -e

LIVE=/run/live/medium/live
MARK='patched: open read-write'

REPORTED=""
fail() { REPORTED=1; echo -e "\n❌ $*"; exit 1; }
installed_kernels() { dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'linux-image-[0-9]*' 2>/dev/null | awk '$1 ~ /^[hi]i/ {print $2}'; }

# check_initrd IMAGE VERSION: encryption support for that kernel + live system + discard-mode patch.
# Structural checks only: they don't prove the image boots.
check_initrd() {
    local img=$1 ver=$2 bad=0 list tmpd
    list=$(lsinitramfs "$img") || return 1
    grep -q 'sbin/cryptsetup$' <<< "$list" || { echo "  missing: cryptsetup"; bad=1; }
    grep -F "lib/modules/$ver/" <<< "$list" | grep -q 'dm-crypt\.ko' || { echo "  missing: dm-crypt for $ver"; bad=1; }
    grep -q 'scripts/live$' <<< "$list" || { echo "  missing: scripts/live"; bad=1; }
    tmpd=$(mktemp -d)
    if unmkinitramfs "$img" "$tmpd" 2>/dev/null && grep -rqs "$MARK" "$tmpd"; then :; else echo "  missing: discard-mode patch"; bad=1; fi
    rm -rf "$tmpd"
    return $bad
}

# --- Safety checks before touching anything ---
[ "$EUID" -eq 0 ] || fail "Run with: sudo kernel-update"
grep -qw persistence-read-only /proc/cmdline && fail "Discard-changes mode: changes would be lost. Reboot into 'Save changes'."
findmnt -no OPTIONS / | grep -q 'upperdir=/run/live/persistence/' || fail "Saved storage isn't in use. Reboot into 'Save changes'."
OLD=$(uname -r)
cmp -s "/boot/vmlinuz-$OLD" "$LIVE/vmlinuz" || fail "The stick's kernel isn't the one running. Reboot into 'Save changes' (and run routine-update) first."
[ "$(installed_kernels | wc -l)" -eq 1 ] || fail "More than one kernel is installed. Run routine-update first; it removes old kernels."
check_initrd "$LIVE/initrd.img.good" "$OLD" > /dev/null || fail "Backup boot image $LIVE/initrd.img.good is missing or failed its checks for $OLD. Fix this first."

echo "Running kernel: $OLD"
echo "If the new kernel doesn't work, restoring your full backup is the way back."
read -rp "Have you made a fresh full backup of the stick? Type YES to continue: " a
[ "$a" = YES ] || fail "Cancelled. Nothing was changed."

# --- Install the new kernel ---
echo -e "\n📦 1/4: Installing the newest kernel..."
apt-mark unhold linux-image-amd64 > /dev/null 2>&1 || true
# However this script exits (success, failure or Ctrl+C), hold the kernel
# metapackage again, so a later routine-update can't pull in a kernel by itself.
# If it stopped on an error it didn't report itself, say so.
on_exit() {
    local rc=$?
    apt-mark hold linux-image-amd64 > /dev/null 2>&1 || true
    if [ "$rc" -ne 0 ] && [ -z "$REPORTED" ]; then
        echo -e "\n❌ kernel-update stopped unexpectedly (code $rc). The kernel update is incomplete."
        echo "   DON'T REBOOT until you've checked that $LIVE/vmlinuz and initrd.img are a matching, working pair."
    fi
}
trap on_exit EXIT
apt-get update
apt-get install -y linux-image-amd64
NEW=$(installed_kernels | sed 's/^linux-image-//' | sort -V | tail -1)
if [ "$NEW" = "$OLD" ]; then
    apt-mark hold linux-image-amd64 > /dev/null
    echo -e "\n✅ $OLD is already the newest kernel. Nothing changed."
    exit 0
fi
echo "New kernel: $NEW"

# Try to undo the install if something fails. This isn't a full transaction:
# it only reports success for the steps it has actually verified.
rollback() {
    set +e
    local removed=1
    echo -e "\nRemoving the new kernel and putting $OLD's boot files back..."
    apt-get purge -y "linux-image-$NEW" || removed=0
    mount -o remount,rw /run/live/medium
    rm -f "$LIVE"/vmlinuz[0-9]* "$LIVE"/initrd[0-9]*.img "$LIVE"/vmlinuz.new "$LIVE"/initrd.img.new
    cmp -s "/boot/vmlinuz-$OLD" "$LIVE/vmlinuz" || cp "/boot/vmlinuz-$OLD" "$LIVE/vmlinuz"
    check_initrd "$LIVE/initrd.img" "$OLD" > /dev/null || cp "$LIVE/initrd.img.good" "$LIVE/initrd.img"
    sync
    if ! cmp -s "/boot/vmlinuz-$OLD" "$LIVE/vmlinuz" || ! check_initrd "$LIVE/initrd.img" "$OLD" > /dev/null; then
        fail "$1 Putting $OLD's boot files back FAILED. DON'T REBOOT: restore your full backup, or get help."
    fi
    [ "$removed" -eq 1 ] || fail "$1 The stick's boot files are back to $OLD and passed their checks, but removing the new kernel package failed. Run routine-update after rebooting; it removes it."
    fail "$1 The new kernel was removed, and the stick's boot files are back to $OLD and passed their checks."
}

# --- Check the new kernel's boot image ---
echo -e "\n🔐 2/4: Checking the new boot image..."
B=/boot/initrd.img-$NEW
if ! check_initrd "$B" "$NEW"; then
    echo "Rebuilding it once..."
    update-initramfs -u -k "$NEW" || true
    check_initrd "$B" "$NEW" || rollback "The new kernel's boot image failed its checks."
fi
echo "  boot image OK"

# --- Put the new kernel on the stick ---
echo -e "\n💾 3/4: Putting the new kernel on the stick..."
mount -o remount,rw /run/live/medium
cp "/boot/vmlinuz-$NEW" "$LIVE/vmlinuz.new" && cp "$B" "$LIVE/initrd.img.new" && sync \
    && cmp -s "/boot/vmlinuz-$NEW" "$LIVE/vmlinuz.new" && cmp -s "$B" "$LIVE/initrd.img.new" \
    || rollback "Copying to the stick failed (is LIVE full?)."
{ mv "$LIVE/vmlinuz.new" "$LIVE/vmlinuz" && mv "$LIVE/initrd.img.new" "$LIVE/initrd.img" && sync; } || true
if ! cmp -s "/boot/vmlinuz-$NEW" "$LIVE/vmlinuz" || ! cmp -s "$B" "$LIVE/initrd.img"; then
    cp "/boot/vmlinuz-$OLD" "$LIVE/vmlinuz" ; cp "$LIVE/initrd.img.good" "$LIVE/initrd.img" ; sync
    rollback "Swapping in the new kernel failed."
fi
# Stage the new backup boot image first, so an interrupted copy can't leave a broken one.
cp "$LIVE/initrd.img" "$LIVE/initrd.img.good.new" && sync && mv "$LIVE/initrd.img.good.new" "$LIVE/initrd.img.good" && sync
rm -f "$LIVE"/vmlinuz[0-9]* "$LIVE"/initrd[0-9]*.img

# --- Holds: keep the new kernel, let routine-update remove the old one ---
echo -e "\n📌 4/4: Updating kernel holds..."
apt-mark hold linux-image-amd64 "linux-image-$NEW" > /dev/null
apt-mark unhold "linux-image-$OLD" > /dev/null
apt-mark showhold

echo -e "\n✅ The stick now boots $NEW."
echo "Next:"
echo "  1. Reboot into 'Save changes' and check Wi-Fi, sound and the display."
echo "  2. Reboot into 'Discard session changes' and check it starts."
echo "  3. Back in 'Save changes', run: sudo routine-update  (it removes the old kernel)."
echo "If something is wrong, restore your full backup."
