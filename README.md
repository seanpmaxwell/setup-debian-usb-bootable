# Debian Live USB with Encrypted Persistence and a Disposable Session Mode

This tutorial builds a portable **Debian 13 (Trixie) GNOME Live USB**. It has an encrypted (LUKS) persistence partition, and two boot menu entries:

| | **Save changes** | **Discard session changes** |
|---|---|---|
| Unlocks your encrypted data at boot | Yes | Yes |
| Starts from your saved apps, settings and files | Yes | Yes |
| Keeps what you do in this session | Yes | **No.** Everything is forgotten at shutdown |

It boots with **Secure Boot** on, using Debian's own signed shim and GRUB, so there are no keys to enroll on each PC. It updates itself from inside the running system, and it comes with scripts for safe updates, kernel updates, backup and restore.

---

## Contents

- [Why this approach](#why-this-approach)
  - [Goals](#goals)
  - [Why not Kicksecure](#why-not-kicksecure)
  - [Why not Ventoy](#why-not-ventoy)
  - [Trade-offs of this approach](#trade-offs-of-this-approach)
  - [Comparison](#comparison)
  - [Is this for you?](#is-this-for-you)
- [What you end up with](#what-you-end-up-with)
- [What this does and doesn't protect against](#what-this-does-and-doesnt-protect-against)
- [The guides](#the-guides)
- [Sources](#sources)

---

## Why this approach

Ready-made tools already cover parts of this. This section explains what the build is for, how it compares with the two closest alternatives, and what it costs you.

### Goals

1. **Encrypt everything you save.** Your installed apps, settings and files live on a LUKS-encrypted partition on a stick you carry around. If the stick is lost, nothing you saved can be read without the passphrase.
2. **A disposable session that still starts from your saved system.** You don't get a blank, generic system. You get your own setup, and nothing from that session is kept.
3. **Secure Boot on any PC, with nothing to enroll.** You plug the stick into an unfamiliar machine with Secure Boot on, and it boots.
4. **Updates from the stick itself.** You update packages, and when you choose to, the kernel, from inside the running system. You don't rebuild an image on another computer.

### Why not Kicksecure

[Kicksecure](https://www.kicksecure.com/wiki/About) is a security-hardened distribution based on Debian. It's the base that Whonix is built on. It's the closest existing match to these goals, and it gets closer than its reputation as a VM-oriented system suggests.

**What Kicksecure offers for these goals:**

- **Intended use.** It runs on bare metal and in virtual machines. Its official downloads cover VirtualBox, KVM and Qubes, as well as an ISO for real hardware ([About](https://www.kicksecure.com/wiki/About)).
- **Live mode and persistence.** The Kicksecure ISO's live mode has **no persistence at all**: "Nothing you do is saved after you shut it down" ([ISO Live Mode](https://www.kicksecure.com/wiki/ISO_Live_Mode)). The persistent USB route is different. You boot the ISO from one stick and run "Install to Hard Drive" onto a second stick, which gives a normal installed system on USB ([USB Installation](https://www.kicksecure.com/wiki/USB_Installation)). Kicksecure says a ready-made persistent USB image doesn't exist yet because of technical difficulties (same page).
- **Encryption.** Full disk encryption is enabled by default in Kicksecure's installer ([About](https://www.kicksecure.com/wiki/About)). The USB installation page doesn't specifically say that this applies when the target is a USB stick.
- **A disposable session.** On an installed system, Kicksecure's `grub-live` package adds a **LIVE mode** boot entry. In LIVE mode, writes go to RAM, and the disk's filesystems are mounted read-only ([Live Mode](https://www.kicksecure.com/wiki/Live_Mode), [grub-live](https://www.kicksecure.com/wiki/Grub-live)). The grub-live documentation lists it as compatible with full disk encryption. This is very close to this build's "Discard session changes" entry.
- **Secure Boot.** It works with the default Microsoft keys. Out-of-tree kernel modules, such as VirtualBox's, need a MOK key enrolled ([Secure Boot](https://www.kicksecure.com/wiki/Secure_Boot)).
- **Hardening and defaults.** Kicksecure changes a lot of defaults. Examples: separate accounts for daily use and administration, kernel hardening settings, AppArmor profiles, USBGuard, APT updates over Tor, and `sdwdate` instead of unauthenticated NTP for the clock ([About](https://www.kicksecure.com/wiki/About)).

**What Kicksecure does better than this build:**

- **Hardening.** This build is stock Debian GNOME with a few changes: passwordless sudo removed, automatic login off, and an optional separate admin account. Kicksecure's hardening goes much further.
- **No custom patches to maintain.** This build depends on a patched live-boot script and a rebuilt boot image. Kicksecure's LIVE mode is maintained by its developers.
- **Ordinary kernel updates.** An installed Kicksecure system updates its kernel like any Debian install. On this build, kernel updates are a deliberate, separate job.
- **A more careful live mode.** grub-live also remounts other writable filesystems read-only ([grub-live](https://www.kicksecure.com/wiki/Grub-live)).

**Where this build differs:**

- **You stay on plain Debian GNOME,** with Debian's defaults. Kicksecure's defaults, such as Tor-routed updates and its account split, change how the system behaves day to day.
- **You control and understand every piece.** The whole build is a handful of commands that you can read in this tutorial.
- **Portability across PCs isn't documented for Kicksecure.** Kicksecure warns that a USB installed in BIOS mode "may only boot on computers using BIOS", and the same applies to UEFI ([USB Installation](https://www.kicksecure.com/wiki/USB_Installation)). This build is UEFI-only by design.

> [!NOTE]
> This guide hasn't tested an encrypted Kicksecure USB installation with LIVE mode. Based on Kicksecure's documentation, it looks like a reasonable alternative. If you want hardening more than control, try it first.

### Why not Ventoy

[Ventoy](https://www.ventoy.net/) puts many ISO files on one stick and boots any of them from a menu. That's very convenient, but it doesn't fit this build:

1. **The boot image has to be replaced, and Ventoy boots the ISO's own.** Debian 13's stock live boot image (initrd) lacks `cryptsetup` and `dm-crypt`, so it can't unlock encryption ([How it works](docs/01-build-the-stick.md#two-things-this-tutorial-works-around)). This build depends on a rebuilt initrd. Ventoy's Boot Conf Replace plugin can only replace configuration files inside the ISO, such as `grub.cfg` or `isolinux.cfg`, and it doesn't modify the ISO ([Boot Conf Replace](https://www.ventoy.net/en/plugin_bootconf_replace.html)). That leaves two options:
   - **Rebuild the ISO** with your own initrd swapped in. This works, but you'd have to repeat it every time the initrd changes.
   - **Use Ventoy's injection plugin.** It extracts an archive of files into the initramfs at boot ([Injection plugin](https://www.ventoy.net/en/plugin_injection.html)). In theory, you could inject `cryptsetup`, its libraries, the kernel module and the patched script. In practice, that's fragile, and you'd be trusting it with the only copy of your data.
2. **The discard-mode fix also lives in the boot image.** The one-line live-boot patch has to be built into the initrd, so it runs into the same problem.
3. **Updates rewrite the boot image, and they can't reach the ISO.** On this stick, Debian's live tools copy each rebuilt initrd onto the writable LIVE partition, where you check it before rebooting. Under Ventoy, the system boots from a read-only ISO file. Package updates would still be saved to persistence, but initrd rebuilds would never reach the boot path. You'd be back to rebuilding the ISO by hand.
4. **Secure Boot needs a key enrollment on each PC.** Ventoy supports Secure Boot, but on each new computer you enroll Ventoy's key once, in a blue key-manager screen. Some machines also need "Allow Microsoft 3rd Party UEFI CA" turned on in the firmware. Ventoy 1.1.13 and later need a new key enrolled because of the Microsoft UEFI CA 2023 change ([Secure Boot](https://www.ventoy.net/en/doc_secure.html)). For a stick you carry between PCs, that's a real cost.
5. **Encrypted persistence is undocumented.** Ventoy's persistence plugin uses an image file, ext4 by default, with a filesystem label. Its documentation doesn't mention LUKS, and Debian isn't on its tested list. Debian appears only in a note about needing a `persistence.conf` file ([Persistence plugin](https://www.ventoy.net/en/plugin_persistence.html)). This build uses a real LUKS partition, which is the setup Debian's live-boot is designed for.

> [!NOTE]
> **Not confirmed in Ventoy's docs:** points 1–3 assume that Ventoy loads the kernel and initrd from inside the ISO, and that injection can't replace the initrd. That's how Ventoy is generally understood to work, but its documentation doesn't say so directly.

**When Ventoy is the better choice:** when you want **many ISOs on one stick**, for installers, rescue tools and trying out distributions. You can also have both. Ventoy can reserve space at the end of the disk, and you can create your own partitions there ([Disk layout](https://www.ventoy.net/en/doc_disk_layout.html)). You could put this build's three partitions in that space. This guide doesn't cover that setup. In practice, two sticks is simpler.

### Trade-offs of this approach

This approach has real costs:

- **A long setup.** Expect an afternoon: two sticks, a dozen sections, and checks after almost every step.
- **Maintenance habits you have to keep.** After every update, the boot image has to pass two checks before you reboot. The `routine-update` script does this for you, but only if you use it. See [The update rule](docs/02-maintenance.md#the-update-rule).
- **Kernel updates are a deliberate job.** The kernel is held. Upgrading it means making a backup, running `kernel-update`, and testing both modes.
- **The passphrase prompt may assume a US keyboard layout.** On other layouts, pick a passphrase you can type reliably on a US layout.
- **Discard mode can finish leftover writes from your last Save session.** It never saves anything from the discard session itself. But to mount your saved data reliably, it lets the kernel complete unfinished journal writes from the previous Save changes session. In this sense, discard mode isn't strictly read-only at the disk level.
- **You maintain the patch.** If a future live-boot version changes the line the patch edits, `routine-update` warns you, and you'll need to adapt the patch yourself.

### Comparison

| | **This build** | **Kicksecure (USB install + LIVE mode)** | **Ventoy + Debian Live ISO** |
|---|---|---|---|
| Intended use | One portable bare-metal stick | Hardened desktop OS: VMs, bare metal, USB install; base of Whonix | Booting many ISOs from one stick |
| Encrypted saved data on the USB | Yes, a LUKS partition | Full disk encryption by default in the installer; not stated specifically for USB targets | Not documented: the persistence plugin uses an image file, and LUKS isn't mentioned |
| Disposable session from your saved system | Yes, "Discard session changes" | Yes, grub-live "LIVE mode" | Not without a rebuilt initrd |
| Secure Boot on any PC, no key enrollment | Yes, Debian's signed shim and GRUB | Yes, Microsoft keys; extra kernel modules need a MOK key | No, one-time key enrollment on each PC |
| Updates from the stick itself | Yes. Kernel updates are a separate, scripted job | Yes, an ordinary installed system | Packages yes, initrd changes no |
| Hardening | Stock Debian, plus a few changes | Extensive by default | Whatever the ISO ships |
| Many ISOs on one stick | No | No | **Yes**, its main strength |
| Setup effort | High | Moderate, installer-driven | Low for ISOs; high for this goal |
| Control over the system | Full; plain Debian GNOME | Kicksecure's defaults and choices | Limited by the ISO and the plugins |

### Is this for you?

> [!TIP]
> **Follow this tutorial if** you want plain Debian GNOME on a stick you carry between UEFI PCs, with encrypted persistence and a disposable mode. You should be comfortable pasting commands into a terminal and checking their output, and willing to keep a simple update routine.
>
> **Look elsewhere if:**
> - You want a hardened system out of the box: try [Kicksecure](https://www.kicksecure.com/wiki/USB_Installation).
> - You mainly want many ISOs on one stick: use [Ventoy](https://www.ventoy.net/).
> - You need anonymity, or protection against a determined, skilled adversary: this build isn't designed for that. See [what it doesn't protect against](#what-this-does-and-doesnt-protect-against).
> - Your PC only has legacy BIOS: this build is UEFI-only.

---

## What you end up with

- **One Debian system on the stick, with two ways to boot it.** Both boot menu entries use the same partitions. The only difference is where new changes go.
- **Discard session changes** starts from everything you've saved, but sends this session's changes to RAM, so they vanish at shutdown. Use it for:
  - **Amnesic sessions:** browsing, opening untrusted files, or lending the machine to someone, without leaving traces in your saved system.
  - **Trying things safely:** testing settings, apps or updates. If you like the result, redo it in Save changes mode. If not, just reboot.
- **A boot image that can unlock encryption**, with a fix that stops discard mode from silently booting a blank system.
- **Scripts** for safe routine updates, kernel updates, full backups and restores.

How the pieces fit together, in brief:

```text
UEFI firmware ─► shim ─► GRUB ─► kernel + rebuilt initrd ─► live-boot unlocks LUKS ─► overlay of:
                 (Debian-signed)  (from the LIVE partition)                              your saved system (rw or ro)
                                                                                         + Debian base (read-only)
```

The full explanation is in [How it works](docs/01-build-the-stick.md#2-how-it-works).

---

## What this does and doesn't protect against

**It protects:**

- **Your saved data, if the stick is lost or stolen while it's switched off.** Everything you save is on the LUKS partition, and it's only as strong as your passphrase.
- **Your saved system from accidental changes during a discard session.** You start every discard session from the same saved state.

**It doesn't protect against:**

- **Anyone noticing the stick exists, or what's on it.** The EFI and LIVE partitions aren't encrypted. They openly contain a Debian live system and a boot menu, and the third partition is visibly a LUKS volume. Discard mode doesn't hide that the stick or your saved data exists.
- **Tampering with the unencrypted partitions.** Secure Boot checks the boot loader and the kernel. The boot menu (`grub.cfg`) and the boot image (`initrd.img`) aren't signed. Someone with access to the stick could modify them, for example to capture your passphrase. This is the classic "evil maid" attack. Keep the stick with you.
- **A compromised computer.** Malicious firmware, hardware keyloggers, or a compromised machine can see your passphrase and everything you do. Secure Boot doesn't defend against compromised firmware.
- **Someone with admin rights in a discard session.** Discard mode isn't a security barrier. Anyone with `sudo` can deliberately write to the encrypted partition or the boot files. It protects against *accidental* changes.
- **Writes to other drives.** Discard mode only discards changes to the stick's own system. It doesn't stop writes to drives you mount, or to the computer's internal disk.
- **Anything sent over the network.** Sign-ins, cloud uploads and the websites you visit are outside the stick, and aren't discarded.
- **Leftover journal writes.** Discard mode can complete unfinished writes from your last Save changes session (see [Trade-offs](#trade-offs-of-this-approach)). It doesn't write anything new from the discard session itself.
- **Unencrypted backups.** A backup contains your saved system **unencrypted** inside the backup folder, so it must be kept on an encrypted drive. The maintenance guide sets one up.
- **A forgotten passphrase.** Without it, your saved data and its backups can't be recovered.

---

## The guides

1. **[Build the stick](docs/01-build-the-stick.md)**: from two blank USB sticks to a tested, updatable system.
   1. [What you need](docs/01-build-the-stick.md#1-what-you-need)
   2. [How it works](docs/01-build-the-stick.md#2-how-it-works)
   3. [Make the installer stick](docs/01-build-the-stick.md#3-make-the-installer-stick)
   4. [Boot the installer stick](docs/01-build-the-stick.md#4-boot-the-installer-stick)
   5. [Partition the target stick](docs/01-build-the-stick.md#5-partition-the-target-stick)
   6. [Build a boot image that can unlock encryption](docs/01-build-the-stick.md#6-build-a-boot-image-that-can-unlock-encryption)
   7. [Copy the system and install the boot loader](docs/01-build-the-stick.md#7-copy-the-system-and-install-the-boot-loader)
   8. [First boot](docs/01-build-the-stick.md#8-first-boot)
   9. [Make updates safe, then update](docs/01-build-the-stick.md#9-make-updates-safe-then-update)
   10. [Accounts, passwords and tidying up](docs/01-build-the-stick.md#10-accounts-passwords-and-tidying-up)
   11. [Test both modes](docs/01-build-the-stick.md#11-test-both-modes)
   12. [Everyday use](docs/01-build-the-stick.md#12-everyday-use)
   13. [Troubleshooting](docs/01-build-the-stick.md#13-troubleshooting)
2. **[Maintenance](docs/02-maintenance.md)**: updates, kernel updates, backup and restore.
   1. [The scripts](docs/02-maintenance.md#the-scripts)
   2. [The update rule](docs/02-maintenance.md#the-update-rule)
   3. [One-time setup](docs/02-maintenance.md#one-time-setup)
   4. [Routine updates](docs/02-maintenance.md#routine-updates)
   5. [Making a backup](docs/02-maintenance.md#making-a-backup)
   6. [Kernel updates](docs/02-maintenance.md#kernel-updates)
   7. [Restoring a backup](docs/02-maintenance.md#restoring-a-backup)
   8. [Script status](docs/02-maintenance.md#script-status)

The scripts are in [`Maintenance/`](Maintenance/).

---

## Sources

Checked in November 2026:

- Kicksecure wiki: [About](https://www.kicksecure.com/wiki/About), [USB Installation](https://www.kicksecure.com/wiki/USB_Installation), [ISO Live Mode](https://www.kicksecure.com/wiki/ISO_Live_Mode), [Live Mode](https://www.kicksecure.com/wiki/Live_Mode), [grub-live](https://www.kicksecure.com/wiki/Grub-live), [Secure Boot](https://www.kicksecure.com/wiki/Secure_Boot)
- Ventoy docs: [Secure Boot](https://www.ventoy.net/en/doc_secure.html), [Persistence plugin](https://www.ventoy.net/en/plugin_persistence.html), [Injection plugin](https://www.ventoy.net/en/plugin_injection.html), [Boot Conf Replace plugin](https://www.ventoy.net/en/plugin_bootconf_replace.html), [Disk layout](https://www.ventoy.net/en/doc_disk_layout.html)

## License

See [LICENSE](LICENSE).
