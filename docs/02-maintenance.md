# Maintenance

This guide covers the stick's whole life after [the build](01-build-the-stick.md): routine updates, backups, kernel updates and restores. It assumes you finished the build, including the separate `admin` account from [step 10.4](01-build-the-stick.md#104-optional-recommended-a-separate-admin-account).

---

## Contents

1. [The scripts](#the-scripts)
2. [The update rule](#the-update-rule)
3. [One-time setup](#one-time-setup)
4. [Routine updates](#routine-updates)
5. [Making a backup](#making-a-backup)
6. [Kernel updates](#kernel-updates)
7. [Restoring a backup](#restoring-a-backup)
8. [Script status](#script-status)

---

## The scripts

The scripts are in [`Maintenance/`](../Maintenance/).

| Script | Runs from | Installed at | What it does |
|---|---|---|---|
| [`routine-update`](../Maintenance/routine-update.sh) | Your stick, **Save changes** | `/usr/local/sbin` | Updates everything except the kernel, checks the boot image, and restores the backup boot image if the check fails. Reapplies the discard-mode fix after a live-boot update. Removes old kernels after a kernel update |
| [`kernel-update`](../Maintenance/kernel-update.sh) | Your stick, **Save changes** | `/usr/local/sbin` | Installs the newest kernel and puts it on the stick in one go. If the new boot image fails its checks, it removes the new kernel and leaves the stick unchanged |
| [`backup-stick.sh`](../Maintenance/backup-stick.sh) | **Installer stick** | Backup drive, `Maintenance/` | Backs up all three partitions of your stick to a dated folder, then verifies the backup |
| [`restore-stick.sh`](../Maintenance/restore-stick.sh) | **Installer stick** | Backup drive, `Maintenance/` | Puts a backup back onto the same stick, or onto a new one at least as big |
| [`check-mode.sh`](../Maintenance/check-mode.sh) | Your stick, either mode | Anywhere | Prints the current mode (`PERSISTENT` for Save changes, `READ-ONLY` for Discard session changes) and the overlay layers. Run it with `bash check-mode.sh` |

---

## The update rule

> [!IMPORTANT]
> **Update only in Save changes mode, and check the boot image on LIVE before every reboot.**

### Why

The stick always boots the `initrd.img` on the LIVE partition. Updates can rebuild that boot image, and Debian's live tools copy the rebuilt one straight onto LIVE. If a rebuild ever drops encryption support or the discard-mode fix, the stick stops unlocking, or discard mode silently boots a blank system. The checks catch that **before** you reboot, while you can still restore the known-good copy, `initrd.img.good`.

### The easy way: `routine-update`

[`routine-update`](#routine-updates) does all of this for you. It updates, reapplies the fix if live-boot changed, checks the boot image on LIVE, and restores `initrd.img.good` if a check fails. Use it for every update.

### By hand

If you update without the script, for example with `apt` directly:

1. Run the two checks from [step 9.4 of the build](01-build-the-stick.md#94-rebuild-and-check) before rebooting. They confirm that the boot image on LIVE still has encryption support and the discard-mode fix.
2. If a check fails, **don't reboot.** Restore `initrd.img.good` with the [command in step 9.4](01-build-the-stick.md#restore-good-initrd).

### Reapplying the patch after a live-boot update

When live-boot itself is updated, the diverted original (in `/usr/local/share/live-boot-orig/`) gets the new version, and your patched copy stays at the old one. The checks still pass, because the old patched file is kept. To bring in the new version, reapply the patch:

```bash
sudo cp /usr/local/share/live-boot-orig/9990-misc-helpers.sh /usr/lib/live/boot/9990-misc-helpers.sh
sudo sed -i 's|opts="${opts} --readonly"|: # patched: open read-write so the ext4 journal can be replayed; filesystem is still mounted ro|' /usr/lib/live/boot/9990-misc-helpers.sh
sudo update-initramfs -u
```

Then run the checks from [step 9.4](01-build-the-stick.md#94-rebuild-and-check) again. `routine-update` does this automatically.

---

## One-time setup

### Backup drive

You need an external drive for backups. It's encrypted, because a backup contains your saved system unencrypted inside it.

> [!CAUTION]
> **This erases the drive you select. Verify your target device twice.** In Disks, check the size and model, and make sure it isn't your stick or the computer's internal disk. Check again before you confirm **Format**.

1. In **Disks**, select the external drive.
2. Choose **Format Disk** → GPT. Then click **+** and use all the space:
   - Volume Name: `debian-backup`
   - Type: **Ext4**
   - **Password protect volume (LUKS)**: on
3. Unlock and mount it, then make it yours, so that Files can open it. Run this as `admin`, or from the installer stick:
   ```bash
   sudo chown "$USER": "/media/$USER/debian-backup"
   ```
4. Create `Maintenance` and `backup-items` folders. Copy the scripts from this repo's `Maintenance/` folder, and a copy of this guide, into `Maintenance`.

**You should end up with this layout:**

```text
debian-backup/
├── Maintenance/      backup-stick.sh, restore-stick.sh, kernel-update.sh, routine-update.sh, a copy of this guide
└── backup-items/
    └── stick-backup-YYYYMMDD-HHMM/   one per backup (root-only)
```

### Scripts on the stick

Run this as `admin`, in **Save changes**, with the backup drive unlocked:

```bash
sudo install -m 755 /media/admin/debian-backup/Maintenance/kernel-update.sh  /usr/local/sbin/kernel-update
sudo install -m 755 /media/admin/debian-backup/Maintenance/routine-update.sh /usr/local/sbin/routine-update
```

The scripts go in `/usr/local/sbin` because only root can change files there. If they were in someone's home folder, that account could edit them and gain root access the next time they ran. That folder is also on sudo's path, so you can run them by name.

---

## Routine updates

Log in as `admin`, or run `su - admin` from `user`, then:

```bash
sudo routine-update
```

It refuses to run in Discard session changes mode, and after `kernel-update` until you've rebooted.

### What the messages mean

| You see | Meaning | What to do |
|---|---|---|
| **✅ Update complete. Safe to reboot.** | Everything updated, and the boot image on LIVE passed its checks | Reboot when you like |
| **ℹ️ A newer kernel is available** | A kernel update is waiting. The rest of the update still completed | When convenient, do a [kernel update](#kernel-updates) |
| **⚠️ live-boot was updated and the read-only fix no longer applies to it** | The new live-boot no longer has the line the patch changes. The script kept your current patched file, and the boot image passed its checks | It's safe to reboot. Before the next update, adapt the patch as in [step 6.2](01-build-the-stick.md#62-apply-the-discard-mode-fix) |
| **❌ The new boot image failed its checks, so the backup was restored** | A rebuild broke the boot image. `initrd.img.good` is back in place | It's safe to reboot, but find out what went wrong before the next update |
| **❌ … AND restoring the backup failed. DON'T REBOOT** | The boot image on LIVE may not unlock | Don't reboot. Restore `initrd.img.good` with the [command in step 9.4](01-build-the-stick.md#restore-good-initrd) and run the checks |
| **❌ Discard-changes mode** or **❌ Saved storage isn't in use** | You're not in Save changes mode with your saved storage | Reboot into Save changes |
| **❌ The stick has a different kernel than the one running** | You ran `kernel-update` and haven't rebooted yet | Reboot into Save changes first |
| **❌ Kernel not held** | The kernel hold from [step 9.3](01-build-the-stick.md#93-protect-the-boot-image) is missing | Run the `apt-mark hold` command the message shows |
| **❌ Backup boot image … is missing or unreadable** | `initrd.img.good` is gone or damaged | Fix this before you update. Don't update without a working backup boot image |
| The script stops with an apt error and no ✅ or ❌ line | apt failed, and the script stopped before checking the boot image | **Don't reboot.** Run the checks from [step 9.4](01-build-the-stick.md#94-rebuild-and-check) by hand |

---

## Making a backup

A backup has to be made from the **installer stick**. While your stick is running, its saved data keeps changing, so a copy made then can't be trusted.

1. Boot the **installer stick**, with your stick and the backup drive plugged in.
2. Unlock **debian-backup** in Files. Ignore any prompt to unlock your stick.
3. Find your stick:
   ```bash
   lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL
   ```
   It's the one with your stick's model and size, and three partitions: `…1` vfat `EFI`, `…2` ext4 `LIVE`, `…3` crypto_LUKS. For example, a 128 GB stick appears as about 115G.

   Don't pick the backup drive. It has a single crypto_LUKS partition containing `debian-backup`.

   > [!CAUTION]
   > **Verify your target device twice.** Check the model, size and three partitions once more before you run the script. The script also refuses to continue unless the partitions look like this stick's, but don't rely on that alone.

4. Run the script, replacing `sdX`:
   ```bash
   sudo bash /media/user/debian-backup/Maintenance/backup-stick.sh /dev/sdX /media/user/debian-backup/backup-items
   ```
5. Type `YES`, then enter the **stick's** encryption passphrase. The script needs internet once per session, to install `partclone` and `zstd`.
6. **You should see:** `✅ Backup complete`, followed by the backup's size. For reference, the first backup of this build was 4.5 GB.
7. **Eject debian-backup in Files** before you unplug it.

Good to know:

- Files can't open a `stick-backup-…` folder. That's deliberate: the folder holds a readable copy of everyone's saved data, so only root can open it.
- A backup unlocks with the passphrase the stick had **when the backup was made**.
- Before saving, the script runs `e2fsck` on your saved data, to finish any writes left over from the last session. This changes the stick slightly, but it's what makes the copy clean.

---

## Kernel updates

Do this when `routine-update` shows **ℹ️ A newer kernel is available**. The kernel is held during routine updates for the reason explained in [step 9.3](01-build-the-stick.md#93-protect-the-boot-image).

1. **[Make a backup](#making-a-backup).** Restoring it is the way back if the new kernel doesn't work.
2. Boot **Save changes**, log in as `admin`, and run:
   ```bash
   sudo kernel-update
   ```
   Type `YES` to confirm you have a fresh backup.

   **You should see:** `✅ The stick now boots <new version>`, and a list of next steps. If the new boot image fails its checks, the script removes the new kernel, and says the stick still boots the old one and that it's safe to reboot.
3. Reboot into **Save changes**. Check that `uname -r` shows the new version, and that Wi-Fi, sound and the display work.
4. Reboot into **Discard session changes** and check that it starts. If it hangs on a black screen, see [Black screen after the passphrase](01-build-the-stick.md#black-screen-after-the-passphrase).
5. Back in **Save changes**, run `sudo routine-update`. It removes the old kernel.

If the new kernel misbehaves, [restore the backup](#restoring-a-backup).

> [!NOTE]
> `kernel-update` also replaces `initrd.img.good` with the new kernel's boot image, because the backup boot image has to match the kernel on LIVE. After a kernel update, `initrd.img.good` can't take you back to the old kernel. Your full backup can.

---

## Restoring a backup

> [!CAUTION]
> **This erases the whole target stick and replaces it with the backup.** Verify your target device twice, and make sure it isn't the backup drive or the computer's internal disk.

1. Boot the **installer stick**, with the target stick and the backup drive plugged in. Unlock **debian-backup**.
2. List the backups, and find the target stick:
   ```bash
   sudo ls /media/user/debian-backup/backup-items/
   lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL
   ```
   The target can be the same stick, or a new one at least as big.
3. **Verify the target device a second time:** check its model and size in the `lsblk` output again.
4. Run the script, replacing the folder name and `sdX`:
   ```bash
   sudo bash /media/user/debian-backup/Maintenance/restore-stick.sh /media/user/debian-backup/backup-items/stick-backup-YYYYMMDD-HHMM /dev/sdX
   ```
   The script checks the backup's files before it changes anything, then shows the device it's about to erase.
5. Type `ERASE`, then enter the stick passphrase **from the backup date**.
6. **You should see:** `✅ Restore complete`. Shut down, unplug the installer stick, and boot the restored stick.

---

## Script status

- `backup-stick.sh` has been used successfully.
- `restore-stick.sh` and `kernel-update` haven't been run on a real stick yet. The first time you use them, have a fresh backup and allow extra time.
- `routine-update` must not run partway through a kernel update done by hand. Before the new kernel is on the stick, it would remove the new kernel.
