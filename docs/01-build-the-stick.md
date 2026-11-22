# Build the stick

This guide takes you from two blank USB sticks to a working, tested, updatable Debian 13 Live stick with encrypted persistence and two boot modes. For why it's built this way, see the [README](../README.md#why-this-approach).

When you finish, continue with [Maintenance](02-maintenance.md) for routine updates and kernel upgrades.

---

## Contents

1. [What you need](#1-what-you-need)
2. [How it works](#2-how-it-works)
3. [Make the installer stick](#3-make-the-installer-stick)
4. [Boot the installer stick](#4-boot-the-installer-stick)
5. [Partition the target stick](#5-partition-the-target-stick)
6. [Build a boot image that can unlock encryption](#6-build-a-boot-image-that-can-unlock-encryption)
7. [Copy the system and install the boot loader](#7-copy-the-system-and-install-the-boot-loader)
8. [First boot](#8-first-boot)
9. [Make updates safe, then update](#9-make-updates-safe-then-update)
10. [Accounts, passwords and tidying up](#10-accounts-passwords-and-tidying-up)
11. [Test both modes](#11-test-both-modes)
12. [Everyday use](#12-everyday-use)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. What you need

- **Two USB sticks:**
  - **Installer stick:** 8 GB or more. It will be erased.
  - **Target stick:** 32 GB or more. 64–128 GB gives plenty of room for saved apps and files. It will be erased. A fast USB 3 stick makes a big difference.
- **A 64-bit PC with UEFI firmware.** Secure Boot can stay on.
- **An internet connection** during setup.
- **The Debian 13 GNOME Live ISO for amd64** from <https://www.debian.org/CD/live/>. Use the *live* image, not netinst.
- **A tool to write the ISO:** Rufus on Windows (in DD mode), or `dd` on Linux.

> [!WARNING]
> **If the PC runs Windows with BitLocker:** changing Secure Boot or the boot order in the firmware settings can trigger a BitLocker recovery prompt. Find your recovery key before you start. Using the one-time boot menu (often F12) is normally fine.

> [!WARNING]
> **Keyboard layout:** the encryption passphrase prompt at boot may assume a **US keyboard layout**. If you use another layout, choose a passphrase you can type reliably on a US layout, for example letters and numbers only.

### How to run the commands

You paste commands into GNOME Terminal.

- **Some steps set names (shell variables) that later steps use**, such as `DEV`, `SHIM` and `LIVE_UUID`. Keep the same Terminal window open within each section. If a command fails because a name is blank (`linux-image-`, `ls: cannot access ''`), rerun the line that sets it.
- **Press Enter on an empty line before you paste a block.** Otherwise the first characters of the paste can get lost: for example, `NEW=…` can arrive as `W=…`.
- **Most blocks stop by themselves if something fails**, and print an "OK" line when they succeed. If you don't see the OK line, stop and work out why before you continue.

---

## 2. How it works

### The boot chain

```text
UEFI firmware ─► shim (Debian-signed) ─► GRUB (Debian-signed) ─► kernel + boot image ─► live-boot
                                          two menu entries         from the LIVE           asks for the passphrase,
                                                                   partition               assembles the system
```

### Disk layout of the target stick

| # | Size | Format | Contents |
|---|---|---|---|
| 1 | 512 MB | FAT32, partition type *EFI System* | Boot loader and menu (`grub.cfg`) |
| 2 | 8 GB | ext4, labelled `LIVE` | Debian base system (`filesystem.squashfs`), kernel (`vmlinuz`), boot image (`initrd.img`) |
| 3 | the rest | LUKS-encrypted ext4, labelled `persistence` | `persistence.conf` and your saved system |

### Overlay layers

live-boot assembles the running system from layers (overlayfs):

| Layer | Save changes | Discard session changes |
|---|---|---|
| Top: where new changes go | Your encrypted partition | RAM, lost at shutdown |
| Middle | none | Your encrypted partition, mounted **read-only** |
| Bottom | Debian base system (`filesystem.squashfs`, never changes) | Same |

The only difference between the two boot entries is one word on the kernel command line: `persistence-read-only`.

### Two things this tutorial works around

**1. The stock boot image can't unlock encryption.** Debian's live-boot supports encrypted persistence (`persistence-encryption=luks`). But recent official live images ship a boot image (initrd) without `cryptsetup` or the `dm-crypt` module. You check yours in [step 6](#61-check-the-stock-boot-image). If it's missing them, you build a replacement that includes them.

**2. Discard mode can silently boot a blank system.** Your whole system runs from the persistence partition, so it often isn't fully unmounted at shutdown. That leaves its ext4 journal with unfinished writes. In discard mode, live-boot unlocks the partition with `cryptsetup --readonly`, so the kernel can't finish those writes. The mount fails, and live-boot quietly boots the plain system *without* your saved data.

A one-line patch to live-boot removes `--readonly`. The filesystem is still **mounted** read-only. The kernel finishes the pending writes, which your last Save changes session had already committed, and then writes nothing more.

The trade-off: discard mode may complete leftover writes from your previous Save changes session. It never saves anything from the discard session itself.

### Why some files exist in two places

The stick only boots the `vmlinuz` and `initrd.img` on the **LIVE** partition. The firmware needs them before the system exists. They must also sit outside the encryption, because the boot image is what unlocks it.

Inside your system, Debian's tools work in `/boot` as usual. Debian's live tools copy rebuilt boot images from `/boot` onto LIVE automatically, but they **don't** copy a new kernel. That's why you hold the kernel in [step 9](#93-protect-the-boot-image), and why [kernel updates](02-maintenance.md#kernel-updates) are a separate, deliberate job.

---

## 3. Make the installer stick

You write the Debian Live ISO to the installer stick. You boot from it to build the target stick, and you keep it afterwards as your rescue stick.

1. Insert the **installer stick** only.
2. Write the ISO to it.

   > [!CAUTION]
   > **This erases the device you select. Verify your target device twice.** Check its size and model, then check again just before you start writing. Choosing the wrong device here can wipe your computer's internal disk.

   - **Windows (Rufus):** select the stick and the ISO, choose GPT and UEFI (non-CSM), click Start, and choose **DD mode** if asked.
   - **Linux:** first identify the stick by its size and model:
     ```bash
     lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL
     ```
     Then run this, replacing `/dev/sdX` with the installer stick:
     ```bash
     sudo dd if=debian-live-13*-amd64-gnome.iso of=/dev/sdX bs=4M status=progress conv=fsync
     ```
3. Eject it safely.

**You should see:** `dd` ends with a summary of bytes copied, or Rufus says it's ready.

---

## 4. Boot the installer stick

1. With only the installer stick plugged in, restart and open the one-time boot menu (often F12, F11, F9 or Esc). Choose the **UEFI** entry for the stick.
2. In the Debian menu, choose **Live system**.
3. When the desktop appears, connect to the internet, then **plug in the target stick**.

> [!WARNING]
> **Don't use "Install Debian" (Calamares).** It makes a *full installation*, not a live system with persistence. No choice of partitions inside it will produce what this tutorial builds.

---

## 5. Partition the target stick

You create the three partitions from [the disk layout](#disk-layout-of-the-target-stick), with encryption on the third one.

### 5.1 Create the partitions in Disks

Open **Disks** and select the target stick in the left sidebar.

> [!CAUTION]
> **The next step erases the selected drive. Verify your target device twice.** In Disks, check the size and model of the drive you selected. Make sure it's the target stick, not the installer stick you booted from or the computer's internal disk. Check again before you confirm **Format**.

1. **Start fresh:** in the drive menu (top right), choose **Format Disk…** → partitioning **GPT**.
2. **EFI partition:** select the free space, then click **+**.
   - Size: **512 MB**
   - Volume Name: `EFI`
   - Type: **FAT**
   - Encryption: off

   Then select the new partition, open the gear menu → **Edit Partition…**, and set **Type** to **EFI System**. The partition type matters: naming the volume `EFI` isn't enough.
3. **LIVE partition:** select the free space, then click **+**.
   - Size: **8 GB**
   - Volume Name: `LIVE`
   - Type: **Ext4**
   - Password protect (LUKS): **off**
4. **Persistence partition:** select the free space, then click **+**.
   - Size: **all remaining space**
   - Volume Name: `persistence` (exactly this, lowercase)
   - Type: **Ext4**
   - **Password protect volume (LUKS): on**

   Choose your encryption passphrase. Remember the [keyboard layout warning](#1-what-you-need).

> [!IMPORTANT]
> **Your encryption passphrase is the only key to your saved data.** If you forget it, everything you saved is lost. Write it down and keep it somewhere safe.

### 5.2 Confirm the layout and set the device name

Open Terminal:

```bash
lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL
```

Find the target stick. It has three partitions: `…1` vfat `EFI`, `…2` ext4 `LIVE`, and `…3` crypto_LUKS with an ext4 `persistence` inside it. `lsblk` shows sizes in GiB, so a "128 GB" stick appears as about 115G.

Set `DEV` to the target stick, **replacing `sdX`**, and check that it isn't the installer stick:

```bash
DEV=/dev/sdX
lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$DEV"
case "$(findmnt -no SOURCE /run/live/medium)" in "$DEV"*) echo "STOP: this is the installer stick" ;; *) echo "OK: not the installer stick" ;; esac
```

**You should see:** the three partitions, and `OK: not the installer stick`. **Continue only if you see both.**

### 5.3 Enable full-system persistence

You write `persistence.conf`, which tells live-boot to keep the whole system on this partition.

In Disks, select the lower `persistence` rectangle (the ext4 volume, not the blue LUKS one) and click **▶** to mount it. If needed, unlock it first with the padlock. Then:

```bash
PERSIST_MNT=$(findmnt -rn -S LABEL=persistence -o TARGET)
if [ -n "$PERSIST_MNT" ]; then
    printf '/ union\n' | sudo tee "$PERSIST_MNT/persistence.conf"
    ls -l "$PERSIST_MNT"
else
    echo "Persistence is not mounted. Stop here."
fi
```

**You should see:** `/ union`, then a listing that includes `persistence.conf`. `/ union` means the whole system persists: installed apps and settings as well as your files.

---

## 6. Build a boot image that can unlock encryption

You build a boot image (initrd) that includes `cryptsetup`, `dm-crypt` and the discard-mode fix. See [Two things this tutorial works around](#two-things-this-tutorial-works-around).

### 6.1 Check the stock boot image

```bash
ls -lh /run/live/medium/live/
lsinitramfs /run/live/medium/live/initrd.img | grep -E 'sbin/cryptsetup$|dm-crypt|scripts/live$'
```

**You should see:**

- **From the first command:** `vmlinuz` and `initrd.img`. If you only see versioned names, such as `vmlinuz-6.12.x-amd64`, use those names when you copy the files in [step 7.3](#73-copy-the-debian-system-and-your-boot-image).
- **From the second command:** probably only `scripts/live`. That confirms the stock image can't unlock encryption.

Either way, continue. You need your own boot image regardless, because the discard-mode fix has to be built into it.

### 6.2 Apply the discard-mode fix

This patches live-boot in the installer session, so that the boot image you build includes the fix:

```bash
sudo sed -i 's|opts="${opts} --readonly"|: # patched: open read-write so the ext4 journal can be replayed; filesystem is still mounted ro|' /usr/lib/live/boot/9990-misc-helpers.sh
grep -n 'patched: open read-write' /usr/lib/live/boot/9990-misc-helpers.sh
```

**You should see:** exactly **one line** from `grep`. If it prints nothing, your live-boot version is different. Run this, and adapt the `sed` command to the line it shows:

```bash
grep -n -- '--readonly' /usr/lib/live/boot/9990-misc-helpers.sh
```

### 6.3 Build the boot image with encryption support

```bash
KVER=$(uname -r) ; echo "Kernel: $KVER"
mkdir -p ~/build && cd ~/build
sudo apt update && sudo apt install -y cryptsetup cryptsetup-initramfs
echo 'CRYPTSETUP=y' | sudo tee -a /etc/cryptsetup-initramfs/conf-hook
sudo mkinitramfs -o ~/build/initrd.img "$KVER"
```

**You should see:** the kernel version, apt installing the two packages, and `mkinitramfs` finishing without an error. Warnings like `Couldn't resolve device overlay`, `Couldn't determine root device` and `fsck hook` are normal on a live system.

<a id="clock-fix"></a>**If `apt` complains that signatures are "not live until…"**, the clock is wrong. Fix it, then repeat the block:

```bash
sudo date -s "$(curl -sI https://deb.debian.org | grep -i '^date:' | cut -d' ' -f2-)"
```

### 6.4 Check the new boot image

```bash
lsinitramfs ~/build/initrd.img | grep -E 'sbin/cryptsetup$|dm-crypt|scripts/live$'
rm -rf /tmp/ird ; mkdir /tmp/ird ; unmkinitramfs ~/build/initrd.img /tmp/ird ; grep -rln 'patched: open read-write' /tmp/ird
```

**You should see:**

- From the first line: `usr/sbin/cryptsetup`, a `dm-crypt.ko…` file, and `scripts/live`.
- From the second line: a path ending in `9990-misc-helpers.sh`.

**Continue only if both checks pass.** These two checks matter for the life of the stick. You run them again after updates (see [The update rule](02-maintenance.md#the-update-rule)).

---

## 7. Copy the system and install the boot loader

You copy the Debian system and your boot image to LIVE, and install Debian's signed boot loader and the boot menu on EFI. Use the same Terminal window, so that `DEV` is still set.

> [!CAUTION]
> **The steps below write to `$DEV`. Verify your target device twice.** Run this and confirm that it still shows the target stick's three partitions (`EFI`, `LIVE`, crypto_LUKS):
> ```bash
> lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$DEV"
> ```
> If it shows anything else, or `DEV` is blank, go back to [step 5.2](#52-confirm-the-layout-and-set-the-device-name).

### 7.1 Download Debian's signed boot loader files

The files are downloaded and unpacked, not installed:

```bash
cd ~/build && apt download shim-signed grub-efi-amd64-signed && for f in *.deb; do dpkg-deb -x "$f" extract; done
SHIM=$(find ~/build/extract -name shimx64.efi.signed | head -1) ; GRUBEFI=$(find ~/build/extract -name grubx64.efi.signed | head -1)
echo "shim: $SHIM" ; echo "grub: $GRUBEFI"
```

**You should see:** a file path after both `shim:` and `grub:`.

### 7.2 Mount the EFI and LIVE partitions

```bash
sudo umount ${DEV}1 ${DEV}2 2>/dev/null
sudo mkdir -p /mnt/efi /mnt/live
sudo mount ${DEV}1 /mnt/efi && sudo mount ${DEV}2 /mnt/live && echo "MOUNTED OK"
```

**You should see:** `MOUNTED OK`.

### 7.3 Copy the Debian system and your boot image

The base system file is about 3 GB and takes a few minutes. `cp` prints nothing until each file is done.

```bash
mountpoint -q /mnt/live && sudo mkdir -p /mnt/live/live && \
sudo cp -v /run/live/medium/live/vmlinuz /run/live/medium/live/filesystem.squashfs /run/live/medium/live/filesystem.packages /mnt/live/live/ && \
sudo cp -v ~/build/initrd.img /mnt/live/live/initrd.img && \
sudo cp ~/build/initrd.img /mnt/live/live/initrd.img.good && echo "COPY OK"
```

**You should see:** each copied file listed, then `COPY OK`.

`initrd.img.good` is a known-good backup of the boot image. You use it if a future rebuild goes wrong.

### 7.4 Install the boot loader

```bash
mountpoint -q /mnt/efi && sudo mkdir -p /mnt/efi/EFI/BOOT /mnt/efi/EFI/debian && \
sudo cp -v "$SHIM" /mnt/efi/EFI/BOOT/BOOTX64.EFI && \
sudo cp -v "$GRUBEFI" /mnt/efi/EFI/BOOT/grubx64.efi && echo "BOOTLOADER OK"
```

**You should see:** `BOOTLOADER OK`.

### 7.5 Write the boot menu

Debian's signed GRUB reads `EFI/debian/grub.cfg`, and a copy goes in `EFI/BOOT/` as well.

```bash
LIVE_UUID=$(sudo blkid -s UUID -o value ${DEV}2) ; echo "LIVE UUID: $LIVE_UUID"
[ -n "$LIVE_UUID" ] && sudo tee /mnt/efi/EFI/debian/grub.cfg > /dev/null <<EOF
set timeout=10
set default=0

insmod part_gpt
insmod ext2
search --no-floppy --fs-uuid --set=root $LIVE_UUID

menuentry "Debian Live - Save changes" {
    linux  /live/vmlinuz boot=live components persistence persistence-encryption=luks
    initrd /live/initrd.img
}

menuentry "Debian Live - Discard session changes" {
    linux  /live/vmlinuz boot=live components persistence persistence-encryption=luks persistence-read-only
    initrd /live/initrd.img
}
EOF
sudo cp /mnt/efi/EFI/debian/grub.cfg /mnt/efi/EFI/BOOT/grub.cfg && sudo cat /mnt/efi/EFI/BOOT/grub.cfg
```

**You should see:** the printed menu, with a UUID at the end of the `search` line, not a blank.

**Optional: hide the boot messages.** Add `quiet` after `components` on both `linux` lines. Without it, you see kernel messages scroll past during startup and shutdown. They're harmless, and useful for troubleshooting.

**Optional: password-protect menu editing.** Generate a hash with `grub-mkpasswd-pbkdf2`. Near the top of the menu, add `set superusers="grubadmin"` and `password_pbkdf2 grubadmin <hash>`. Add `--unrestricted` after each entry's title. Both entries still boot without a password, but editing them needs one.

### 7.6 Unmount everything and lock the encrypted partition

```bash
sync ; sudo umount /mnt/efi /mnt/live
PM=$(findmnt -rn -S LABEL=persistence -o TARGET) ; [ -n "$PM" ] && sudo umount "$PM"
udisksctl lock -b ${DEV}3
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS $DEV
```

**You should see:** the final listing shows no mount points.

---

## 8. First boot

1. Shut down and **unplug the installer stick**. It holds the same live files, and the system could otherwise pick it up by mistake.
2. Boot the target stick from the one-time boot menu, choosing its **UEFI** entry.
3. Choose **Debian Live - Save changes**, and enter your passphrase. Nothing shows on screen while you type.
4. The desktop logs in automatically as Debian Live's default account, `user`, whose password is `live`. You change that in [step 10](#10-accounts-passwords-and-tidying-up).

Open Terminal and check that your encrypted storage is in use:

```bash
findmnt -no OPTIONS / | grep -oE '(lower|upper)dir=[^,]*'
```

**You should see:** an `upperdir` under **`/run/live/persistence/`**. If it shows `/run/live/overlay` instead, the system started without your saved storage. See [Troubleshooting](#13-troubleshooting).

> [!IMPORTANT]
> **Do steps 9 and 10 in Save changes mode**, or they're lost at shutdown. **Don't install or update anything until step 9 is done.**

---

## 9. Make updates safe, then update

Updates can rebuild the boot image, and Debian's live tools copy the rebuilt one **straight onto the LIVE partition**. Without this step, the first rebuild would drop encryption support and the discard-mode fix, and the stick would stop unlocking.

### 9.1 Package sources

The ISO's own package source no longer exists, and security updates aren't set up yet. Replace the sources:

```bash
sudo mkdir -p /etc/apt/sources-backup && sudo mv /etc/apt/sources.list /etc/apt/sources.list.d/* /etc/apt/sources-backup/ 2>/dev/null ; true
sudo tee /etc/apt/sources.list.d/debian.sources > /dev/null <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
sudo apt update
```

**You should see:** `trixie`, `trixie-updates` and `trixie-security` listed, with no errors. For "not live until…" errors, use the [clock fix](#clock-fix) from step 6.3.

### 9.2 Automatic time sync

```bash
sudo apt install -y systemd-timesyncd && sudo timedatectl set-ntp true
```

Set your time zone in **Settings → System → Date & Time**.

If the PC also runs Windows, keep the hardware clock in local time, so that both systems agree:

```bash
sudo timedatectl set-local-rtc 1 --adjust-system-clock
```

### 9.3 Protect the boot image

```bash
sudo apt-mark hold linux-image-amd64 linux-image-$(uname -r)
sudo apt install -y cryptsetup cryptsetup-initramfs
echo 'CRYPTSETUP=y' | sudo tee -a /etc/cryptsetup-initramfs/conf-hook
sudo mkdir -p /usr/local/share/live-boot-orig
sudo dpkg-divert --local --rename --divert /usr/local/share/live-boot-orig/9990-misc-helpers.sh --add /usr/lib/live/boot/9990-misc-helpers.sh
sudo cp /usr/local/share/live-boot-orig/9990-misc-helpers.sh /usr/lib/live/boot/9990-misc-helpers.sh
sudo sed -i 's|opts="${opts} --readonly"|: # patched: open read-write so the ext4 journal can be replayed; filesystem is still mounted ro|' /usr/lib/live/boot/9990-misc-helpers.sh
grep -n 'patched: open read-write' /usr/lib/live/boot/9990-misc-helpers.sh
```

**You should see:** the patched line printed by the last command.

> [!WARNING]
> Installing `cryptsetup-initramfs` may rebuild the boot image partway through this block. That's fine, because step 9.4 rebuilds it properly. But **don't reboot until 9.4 passes.**

What each part does:

- **Holding the kernel** keeps the stick's kernel, boot image and drivers matched. The stick always boots the kernel on LIVE. An ordinary kernel update would install new drivers, and eventually remove the old ones, while the stick kept booting the old kernel. Everything else still updates normally. Upgrading the kernel is a deliberate job: see [Kernel updates](02-maintenance.md#kernel-updates).
- **`CRYPTSETUP=y`** makes every future rebuild include encryption support.
- **`dpkg-divert`** stops live-boot updates from overwriting your patched file. The package's version is stored in a separate folder instead, because live-boot loads every file in its own folder.

### 9.4 Rebuild and check

```bash
sudo update-initramfs -u
L=/run/live/medium/live/initrd.img
lsinitramfs "$L" | grep -E 'sbin/cryptsetup$|dm-crypt|scripts/live$'
rm -rf /tmp/ird ; mkdir /tmp/ird ; unmkinitramfs "$L" /tmp/ird ; grep -rln 'patched: open read-write' /tmp/ird
```

**You should see:** the same two passing checks as in [step 6.4](#64-check-the-new-boot-image): `usr/sbin/cryptsetup`, a `dm-crypt.ko…` file and `scripts/live`, then a path ending in `9990-misc-helpers.sh`. These check the boot image **on LIVE**, which is the one the stick actually boots.

<a id="restore-good-initrd"></a>

> [!CAUTION]
> **If either check fails, don't reboot.** Restore the known-good backup instead:
> ```bash
> sudo mount -o remount,rw /run/live/medium && sudo cp /run/live/medium/live/initrd.img.good /run/live/medium/live/initrd.img && sync
> ```

These are the checks you run after every update from now on. [The update rule](02-maintenance.md#the-update-rule) explains the habit, and the `routine-update` script automates it.

### 9.5 First full update

```bash
sudo apt full-upgrade -y
```

Let it finish. Interrupting apt partway through leaves packages half-installed. Then **run the two checks from [9.4](#94-rebuild-and-check) again before rebooting.**

The live image includes many LibreOffice language packs. To remove all but English (adjust for your language), run this, and check apt's list before you confirm:

```bash
sudo apt purge $(dpkg -l 'libreoffice-help-*' 'libreoffice-l10n-*' | awk '/^ii/{print $2}' | grep -vE 'help-en-us|help-common')
```

---

## 10. Accounts, passwords and tidying up

Stay in Save changes mode. You turn the throwaway live defaults into settings that are safe for a persistent system.

### 10.1 Remove the installer

Running it by mistake could erase a disk:

```bash
sudo apt purge -y calamares calamares-settings-debian && sudo apt autoremove -y ; rm -f ~/Desktop/*calamares*.desktop
```

**You should see:** apt removing the Calamares packages without errors.

### 10.2 Set a real password and turn off automatic login

```bash
passwd
sudo sed -i -e 's/^AutomaticLoginEnable=.*/AutomaticLoginEnable=false/' -e 's/^TimedLoginEnable=.*/TimedLoginEnable=false/' /etc/gdm3/daemon.conf
grep -nE '^(Automatic|Timed)Login' /etc/gdm3/daemon.conf
```

`passwd` asks for the current password (`live`), then your new one twice.

**You should see:** both `…Enable` lines say `false`.

Debian Live uses *timed* login, which the Settings → Users toggle doesn't show or control. That's why you change it in the config file.

### 10.3 Remove passwordless sudo

Debian Live lets `user` run `sudo` with no password, through `/etc/sudoers.d/live`. That's fine for a throwaway session, but not for a persistent system. This keeps sudo, but requires the password:

```bash
sudo usermod -aG sudo user
sudo rm -f /etc/sudoers.d/live
sudo -k ; sudo whoami
```

**You should see:** a prompt for your new password, then `root`. If it says `user is not in the sudoers file`, reboot (into Save changes): the group change takes effect then.

Debian Live's first-boot setup records what it has already done, and won't recreate these settings.

### 10.4 Optional, recommended: a separate admin account

Using a separate account for admin work, and an everyday account without sudo, limits what a mistake or a malicious program can do.

> [!WARNING]
> **Confirm that the new account works before you take sudo away from the old one.** Otherwise you can lock yourself out of admin access.

```bash
sudo adduser admin
sudo usermod -aG sudo admin
```

Test it interactively. `su -c 'sudo …'` won't work, because sudo needs a terminal to ask for the password:

```bash
su - admin
sudo -k ; sudo whoami
exit
```

**Only after that printed `root`**, remove sudo from `user`:

```bash
sudo gpasswd -d user sudo
getent group sudo
sudo grep -rn NOPASSWD /etc/sudoers /etc/sudoers.d/ || echo "no passwordless sudo rules left"
```

**You should see:**

- `getent group sudo` lists only `admin`.
- The last line says `no passwordless sudo rules left`.

From now on, do admin work by logging in as `admin`, or with `su - admin` from the everyday account.

To change an account's display name (for example from "Debian Live user"), run `sudo chfn -f "New Name" user` as `admin`. You can also use **Settings → System → Users**, after unlocking it.

---

## 11. Test both modes

You confirm that Save changes keeps data, and that Discard session changes loads it but keeps nothing.

1. Boot **Save changes**, log in, and create a test file:
   ```bash
   echo saved > ~/saved-test.txt
   ```
2. Reboot into **Discard session changes**, log in, and check:
   ```bash
   cat ~/saved-test.txt ; findmnt -no OPTIONS / | grep -oE '(lower|upper)dir=[^,]*' ; touch ~/discard-test.txt
   ```
   **You should see:**
   - `saved`, so your saved data loaded
   - a `lowerdir` that includes `/run/live/persistence/…`
   - an `upperdir` under `/run/live/overlay`
3. Reboot into **Save changes** and check:
   ```bash
   ls ~/saved-test.txt ~/discard-test.txt
   ```
   **You should see:** `saved-test.txt` listed, and "No such file or directory" for `discard-test.txt`.

If all three steps pass, the stick works. Delete the test file with `rm ~/saved-test.txt`.

<a id="quick-mode-check"></a>**Quick mode check, at any time:**

```bash
grep -qw persistence-read-only /proc/cmdline && echo "DISCARD mode" || echo "SAVE mode"
```

---

## 12. Everyday use

### Using discard mode well

- **To keep anything from a discard session,** copy it somewhere else before you shut down, for example to another drive. Otherwise it's gone.
- **To keep a setting you tried in discard mode,** reboot into Save changes and set it again there.
- **Run updates only in Save changes mode.** In discard mode they're thrown away at shutdown.
- **Know its limits.** Discard mode doesn't stop writes to other drives, isn't a barrier against anyone with sudo, and doesn't undo anything sent over the network. See [What this does and doesn't protect against](../README.md#what-this-does-and-doesnt-protect-against).

### Updating

Update only in Save changes mode, and check the boot image before every reboot. [The update rule](02-maintenance.md#the-update-rule) explains why, and how the `routine-update` script does it for you.

### Shutting down

- **Shut down from the menu.** Pulling the stick or cutting power in Save changes mode can lose recent changes, or damage the saved system.
- <a id="slow-shutdown"></a>**If shutdown pauses** at `Job session-N.scope/stop running (… / 1min 30s)`, a program in your session is slow to quit. Wait: systemd force-closes it after 90 seconds and carries on. To find out which program it was, boot Save changes and run:
  ```bash
  journalctl -b -1 --no-pager | grep -iE 'timed out|killing process' | tail
  ```
  A common cause is a Terminal still running `sudo -i` or `su -`. To shorten the wait to 15 seconds, run this as `admin` in Save changes:
  ```bash
  sudo mkdir -p /etc/systemd/system.conf.d
  printf '[Manager]\nDefaultTimeoutStopSec=15s\n' | sudo tee /etc/systemd/system.conf.d/shutdown-timeout.conf
  ```

### Disk space over time

When packages update, the old versions stay in the read-only base image and the new versions are stored in your persistence partition. So the persistence partition slowly fills with replaced files. That's normal for a live system, and it's why the stick should be generously sized. Check usage with `df -h /`.

---

## 13. Troubleshooting

### Boot problems

| Symptom | Likely cause | Fix |
|---|---|---|
| No passphrase prompt, and a fresh system (welcome tour) in both modes | The boot image lacks encryption support, usually because an update rebuilt it before step 9 was done | Restore `initrd.img.good` ([step 9.4](#restore-good-initrd)). If the stick won't boot, boot the installer stick, mount the target's LIVE partition, and copy `live/initrd.img.good` over `live/initrd.img` |
| Save changes works, but discard mode shows a fresh system after the passphrase | The discard-mode fix is missing from the boot image | Reapply the patch and rebuild ([Reapplying the patch](02-maintenance.md#reapplying-the-patch-after-a-live-boot-update)), then run the checks |
| Black screen after the passphrase, usually in discard mode on the first boot after an update | Often a one-off hang | See [Black screen after the passphrase](#black-screen-after-the-passphrase) below |
| `grub>` prompt instead of the menu | GRUB can't find `grub.cfg` | Check that both copies exist on the EFI partition: `EFI/debian/grub.cfg` and `EFI/BOOT/grub.cfg` |
| "Verification failed" with Secure Boot on | Wrong boot loader files | Repeat [step 7.4](#74-install-the-boot-loader) with the `.signed` files from 7.1 |
| `upperdir` is under `/run/live/overlay` in Save changes mode | The system started without your saved storage | Check the first two rows. If the journal is unfinished, see [Finish an unfinished journal by hand](#finish-an-unfinished-journal-by-hand) |
| Passphrase rejected although you're sure it's right | The prompt may assume a US keyboard layout | Type it as it would be typed on a US layout. See [What you need](#1-what-you-need) |

### Black screen after the passphrase

This has happened once, in discard mode, on the first boot after an update.

1. Press **Ctrl+Alt+F3**. If a text login appears, log in as `admin`, run this, and photograph the screen:
   ```bash
   systemctl --failed --no-pager ; journalctl -b -p err --no-pager | tail -25
   ```
2. Otherwise, hold the power button and boot again. That's safe in discard mode. Last time, the second try worked.

### Updates and packages

| Symptom | Likely cause | Fix |
|---|---|---|
| `apt`: "Not live until…" | The clock is wrong | [Clock fix](#clock-fix) in step 6.3, then [step 9.2](#92-automatic-time-sync) |
| `apt`: `file:/run/live/medium … not found` | The ISO's package source is still set up | [Step 9.1](#91-package-sources) |
| `cp: … Read-only file system` when writing to LIVE | LIVE is mounted read-only | Run `sudo mount -o remount,rw /run/live/medium` first |
| `routine-update` or `kernel-update` stops with ❌ | One of the scripts' safety checks failed | See [What the messages mean](02-maintenance.md#what-the-messages-mean) |

### Accounts and desktop

| Symptom | Likely cause | Fix |
|---|---|---|
| `sudo: a terminal is required to read the password` | sudo was run through `su -c '…'` | Run `su - admin` interactively, then `sudo` |
| Logged in automatically, although Settings shows automatic login off | GDM timed login | [Step 10.2](#102-set-a-real-password-and-turn-off-automatic-login) |
| `mount: (hint) your fstab has been modified…` | Debian Live rewrites `/etc/fstab` at startup | Harmless; ignore it |
| Files: "You do not have the permissions necessary…" on a newly formatted ext4 drive | Its top folder belongs to root | Run `sudo chown "$USER": /media/$USER/<volume>` |
| Shutdown pauses for 90 seconds | A program is slow to quit | See [Shutting down](#slow-shutdown) |

### Finish an unfinished journal by hand

Do this from a session where persistence isn't loaded, such as the installer stick.

> [!CAUTION]
> **Verify your target device twice.** Run `lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL` and make sure `sdX3` is the stick's crypto_LUKS partition, not a partition on another drive.

Replace `sdX3` with the encrypted partition:

```bash
sudo cryptsetup open /dev/sdX3 persistfix && sudo e2fsck -f -p /dev/mapper/persistfix ; sudo cryptsetup close persistfix
```

### Forgotten encryption passphrase

The saved system can't be recovered. Start again from [step 5](#5-partition-the-target-stick), or restore a full backup if you have one ([Back up first](02-maintenance.md#back-up-first)). A backup of the whole stick unlocks with the passphrase the stick had when the backup was made.
