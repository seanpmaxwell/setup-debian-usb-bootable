# Maintenance

This guide covers keeping the stick up to date after [the build](01-build-the-stick.md): routine updates and kernel updates. It assumes you finished the build, including the separate `admin` account from [step 10.4](01-build-the-stick.md#104-optional-recommended-a-separate-admin-account).

---

## Contents

1. [The scripts](#the-scripts)
2. [The update rule](#the-update-rule)
3. [Install the scripts](#install-the-scripts)
4. [Routine updates](#routine-updates)
5. [Kernel updates](#kernel-updates)
6. [Script status](#script-status)

---

## The scripts

The scripts are in [`Maintenance/`](../Maintenance/).

| Script | Runs from | Installed at | What it does |
|---|---|---|---|
| [`routine-update`](../Maintenance/routine-update.sh) | Your stick, **Save changes** | `/usr/local/sbin` | Updates everything except the kernel, checks the boot image, and restores the backup boot image if the check fails. Reapplies the discard-mode fix after a live-boot update. Removes old kernels after a kernel update |
| [`kernel-update`](../Maintenance/kernel-update.sh) | Your stick, **Save changes** | `/usr/local/sbin` | Installs the newest kernel and puts it on the stick in one go. If something fails, it tries to remove the new kernel and put the old boot files back, and reports exactly what it verified. It isn't a full transaction, so keep a full backup |

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

## Install the scripts

Copy this repo's `Maintenance/` folder somewhere the stick can read it, for example a USB drive or your home folder. Then run this as `admin`, in **Save changes**, replacing `/path/to/Maintenance` with where you put it:

```bash
cd /path/to/Maintenance
sudo install -m 755 kernel-update.sh  /usr/local/sbin/kernel-update
sudo install -m 755 routine-update.sh /usr/local/sbin/routine-update
```

**You should see:** no output. `ls -l /usr/local/sbin` lists both scripts, owned by root.

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
| **ℹ️ A newer kernel is available** | A kernel update is waiting. The rest of the update still completed | When convenient, [back up](#back-up-first) and do a [kernel update](#kernel-updates) |
| **⚠️ live-boot was updated and the discard-mode patch no longer applies to it** | The new live-boot no longer has the line the patch changes. The script kept your current patched file, and the boot image passed its checks | It's safe to reboot. Before the next update, adapt the patch as in [step 6.2](01-build-the-stick.md#62-apply-the-discard-mode-fix) |
| **❌ The new boot image failed its checks, so the backup boot image was restored** | A rebuild broke the boot image. `initrd.img.good` is back in place and passed the same checks | It's safe to reboot, but find out what went wrong before the next update |
| **❌ … AND restoring the backup failed. DON'T REBOOT** | The boot image on LIVE may not unlock | Don't reboot. Restore `initrd.img.good` with the [command in step 9.4](01-build-the-stick.md#restore-good-initrd) and run the checks |
| **❌ Discard-changes mode** or **❌ Saved storage isn't in use** | You're not in Save changes mode with your saved storage | Reboot into Save changes |
| **❌ The stick has a different kernel than the one running** | You ran `kernel-update` and haven't rebooted yet | Reboot into Save changes first |
| **❌ Kernel not held** | The kernel hold from [step 9.3](01-build-the-stick.md#93-protect-the-boot-image) is missing | Run the `apt-mark hold` command the message shows |
| **❌ Backup boot image … is missing or failed its checks** | `initrd.img.good` is gone, damaged, or doesn't match the running kernel | Fix this before you update. Don't update without a working backup boot image |
| **❌ routine-update stopped unexpectedly** | A command failed partway, for example apt, before the boot image was checked | **Don't reboot.** Run the checks from [step 9.4](01-build-the-stick.md#94-rebuild-and-check) by hand, and fix the error before updating again |

---

## Kernel updates

Do this when `routine-update` shows **ℹ️ A newer kernel is available**. The kernel is held during routine updates for the reason explained in [step 9.3](01-build-the-stick.md#93-protect-the-boot-image).

### Back up first

> [!IMPORTANT]
> **Make a full backup of the stick before every kernel update.** If the new kernel doesn't work, restoring that backup is your way back. `kernel-update` replaces `initrd.img.good` with the new kernel's boot image, because the backup boot image has to match the kernel on LIVE. After a kernel update, `initrd.img.good` can't take you back to the old kernel.

The backup should be an image of the **whole stick**, made **offline**: from the installer stick, not from the stick itself. While your stick is running, its saved data keeps changing, so a copy made then can't be trusted. A whole-stick image covers everything you'd need to restore: the partition table, the EFI and LIVE partitions, and the complete encrypted partition, including its LUKS header.

1. Boot the **installer stick**, with your stick and a backup drive plugged in. Don't unlock or mount your stick.
2. In **Disks**, select your stick, the whole drive rather than a partition. Check its model and size.
3. In the drive menu, choose **Create Disk Image…**, and save the image on the backup drive. The image is as big as the whole stick, so the backup drive needs at least that much free space.

To restore, use **Restore Disk Image…** in the same menu, onto a stick at least as big as the original.

> [!CAUTION]
> **Restoring erases the stick you restore onto. Verify your target device twice:** check its model and size, and make sure it isn't the backup drive or the computer's internal disk.

Good to know:

- **The image stays encrypted where it matters.** The encrypted partition is copied as it is, so your saved data stays encrypted in the image. The EFI and LIVE partitions weren't encrypted to begin with.
- **It unlocks with the passphrase the stick had when you made it.** Changing the stick's passphrase later doesn't change existing backups.
- **A system-snapshot tool such as Timeshift isn't a substitute.** It won't normally cover the EFI and LIVE partitions or the LUKS header, which you need for a bootable stick, and it hasn't been tested on this live setup. Use it, if at all, in addition to a whole-stick image. A file-level backup of your saved system is unencrypted, so store it on an encrypted drive.
- **Test a restore** onto a spare stick at least once, before you rely on your backups.

### Run the update

1. Boot **Save changes**, log in as `admin`, and run:
   ```bash
   sudo kernel-update
   ```
   It asks whether you've made a fresh full backup of the stick. Type `YES` to continue.

   **You should see:** `✅ The stick now boots <new version>`, and a list of next steps. If something fails, the script tries to remove the new kernel and put the old boot files back. It then reports what it verified: that the old boot files are back and passed their checks, whether removing the new kernel package failed, or, if putting the old boot files back failed, that you mustn't reboot. If it says it stopped unexpectedly, don't reboot until the boot files have been checked.
2. Reboot into **Save changes**. Check that `uname -r` shows the new version, and that Wi-Fi, sound and the display work.
3. Reboot into **Discard session changes** and check that it starts. If it hangs on a black screen, see [Black screen after the passphrase](01-build-the-stick.md#black-screen-after-the-passphrase).
4. Back in **Save changes**, run `sudo routine-update`. It removes the old kernel.

If the new kernel misbehaves, restore your backup.

---

## Script status

- `kernel-update` has been used successfully on a real stick.
