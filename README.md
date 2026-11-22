# Debian Live USB with Encrypted Persistence and a Disposable Session Mode

This tutorial builds a portable **Debian 13 (Trixie) GNOME Live USB** with an encrypted (LUKS) persistence partition and two boot menu entries: **Save changes** and **Discard session changes**.

It boots with **Secure Boot** on, using Debian's signed boot loader (shim and GRUB), so on most PCs there are no keys to enroll. It updates itself from inside the running system, and it comes with scripts for safe routine updates and kernel updates.

**The guides:**

1. [Build the stick](docs/01-build-the-stick.md): from two blank USB sticks to a tested, updatable system.
2. [Maintenance](docs/02-maintenance.md): routine updates and kernel updates.

---

## Contents

- [Why this approach](#why-this-approach)
  - [Goals](#goals)
  - [Why not Kicksecure](#why-not-kicksecure)
  - [Why not Ventoy](#why-not-ventoy)
- [What you end up with](#what-you-end-up-with)
- [License](#license)

---

## Why this approach

Ready-made tools already cover parts of this. This section explains what the build is for, and why it doesn't use the two closest alternatives.

### Goals

1. **Encrypt everything you save.** Your installed apps, settings and files live on a LUKS-encrypted partition on a stick you carry around. If the stick is lost, nothing you saved can be read without the passphrase.
2. **A disposable session that still starts from your saved system.** You don't get a blank, generic system. You get your own setup, and nothing from that session is kept.
3. **Secure Boot without enrolling keys.** You plug the stick into an unfamiliar UEFI PC with Secure Boot on, and it boots. This works on PCs whose firmware trusts Microsoft's third-party UEFI certificate, which Debian's shim is signed with. Most do, but some newer PCs turn that trust off by default.
4. **Updates from the stick itself.** You update packages, and when you choose to, the kernel, from inside the running system. You don't rebuild an image on another computer.

### Why not Kicksecure

[Kicksecure](https://www.kicksecure.com/wiki/About) is a security-hardened distribution based on Debian, and the base that Whonix is built on. It's the closest existing match to these goals. But its hardened defaults take extra setup before it's comfortable as an everyday desktop, and it's a niche system. Debian Live is widely used, general purpose, and works out of the box.

### Why not Ventoy

[Ventoy](https://www.ventoy.net/) boots many ISO files from one stick. It's great for that, but it doesn't fit this build:

- **It boots the ISO's own boot image, which can't unlock encryption.** This build depends on a rebuilt initrd with `cryptsetup`, `dm-crypt` and the discard-mode patch (see [How it works](docs/01-build-the-stick.md#two-things-this-tutorial-works-around)). Ventoy's plugins can replace the ISO's menu files or inject extra files at boot, but neither replaces the initrd ([Boot Conf Replace](https://www.ventoy.net/en/plugin_bootconf_replace.html), [Injection](https://www.ventoy.net/en/plugin_injection.html)). In practice, you'd rebuild the ISO every time the initrd changes.
- **Updates can't reach the boot image.** On this stick, rebuilt initrds land on the writable LIVE partition. Under Ventoy, the system boots from a read-only ISO file.
- **Secure Boot needs a key enrolled on each PC** before the stick will boot there ([Secure Boot](https://www.ventoy.net/en/doc_secure.html)).
- **Encrypted persistence isn't documented.** Ventoy's persistence plugin uses an image file, and its documentation doesn't mention LUKS ([Persistence plugin](https://www.ventoy.net/en/plugin_persistence.html)).

**Ventoy is the better choice** if you want many ISOs on one stick, for installers, rescue tools or trying out distributions.

---

## What you end up with

- **One Debian system on the stick, with two ways to boot it.** Both boot menu entries use the same partitions. The only difference is where new changes go.
- **Discard session changes** starts from everything you've saved, but sends this session's changes to RAM, so they vanish at shutdown. Use it for:
  - **Amnesic sessions:** browsing or opening files without changing your saved system. Discard mode isn't a sandbox, though: see [what it doesn't protect against](docs/01-build-the-stick.md#what-this-does-and-doesnt-protect-against).
  - **Trying things safely:** testing settings or apps. If you like the result, redo it in Save changes mode. If not, just reboot. Don't test system updates this way: they can rewrite the boot files on LIVE, which sits outside the disposable layer.
- **A boot image that can unlock encryption**, with a patch that stops discard mode from silently booting a blank system.
- **Scripts** for safe routine updates and kernel updates.

How the pieces fit together, in brief:

```text
UEFI firmware ─► shim ─► GRUB ─► kernel + rebuilt initrd ─► live-boot unlocks LUKS ─► overlay of:
                 (signed boot chain)  (from the LIVE partition)                          your saved system (rw or ro)
                                                                                         + Debian base (read-only)
```

The full explanation is in [How it works](docs/01-build-the-stick.md#2-how-it-works).

---

## License

See [LICENSE](LICENSE).
