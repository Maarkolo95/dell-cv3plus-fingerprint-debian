# Dell ControlVault 3 Plus fingerprint reader on Debian 13

Scripts that make the **Broadcom 58200 / Dell ControlVault 3 Plus** fingerprint reader work on
**Debian 13 (trixie)**, including fingerprint `sudo`, login (SDDM) and KDE Plasma lock-screen unlock.

Out of the box, Debian lists this reader as *unsupported* and `fprintd-list` says
`No devices available`. Dell and Canonical publish a proprietary driver for Ubuntu, but it needs a
build of `libfprint` with plug-in ("TOD", Touch OEM Drivers) support, which Debian doesn't ship.
These scripts build that library, install Dell's driver, and wire everything up. All changes can be undone.

## Symptoms this fixes

You're in the right place if, on Debian (or another distro whose `libfprint` has no TOD support):

- `fprintd-list $USER` prints **`No devices available`**
- `fprintd-enroll` / `fprintd-verify` fail with
  **`Impossible to enroll: GDBus.Error:net.reactivated.Fprint.Error.NoSuchDevice: No devices available`**
- KDE *System Settings → Users → Configure Fingerprint Authentication* or GNOME *Settings → Users →
  Fingerprint Login* shows no reader, or doesn't offer the option at all
- `lsusb` shows **`ID 0a5c:5865 Broadcom Corp. 58200`** (or `5864`, `5866`, `5867`)
- The reader works on Windows (Dell ControlVault / Windows Hello) but not on Linux
- `/usr/lib/udev/hwdb.d/60-autosuspend-libfprint-2.hwdb` lists your ID under *Known unsupported devices*
- After installing a Broadcom driver: **`USB error on device 0a5c:5863 : No such device (it may have been disconnected) [-4]`**,
  or `fprintd-list` shows `found 3 devices`. See [Known issues](#known-issues-and-limitations)

## Laptops with ControlVault 3 Plus

Dell's security advisory [DSA-2025-053](https://www.dell.com/support/kbdoc/en-us/000276106/dsa-2025-053)
lists these models with the **ControlVault 3 Plus** chip. Only the Dell Pro 16 Plus PB16250 has been tested.
For the others, check your USB ID first (next section).

| Line | Models |
|---|---|
| Dell Pro | Pro 13 Plus PB13250, Pro 14 Plus PB14250, **Pro 16 Plus PB16250** (tested), Pro 14 PC14250 |
| Dell Pro Max | Pro Max 14 MC14250, Pro Max 16 MC16250 |
| Dell Pro Rugged | Pro Rugged 13 RA13250, Pro Rugged 14 RB14250 |
| Latitude | 5350, 5450, 5550, 7350, 7350 Detachable, 7450, 7650, 9450 |
| Precision | 3490, 3590, 3591, 5490, 5690 |

If you've got it working on another model, please open an issue or PR so it can be added to the list.

**Other distros:** the scripts target Debian 13 (trixie). Ubuntu users should first try Dell's
packaged driver (`apt search libfprint-2-tod1-broadcom-cv3plus`). Fedora and Arch users can
find community packages of the same driver (Fedora COPR, AUR `libfprint-2-tod1-broadcom-cv3plus`).
The steps in this repo show what those packages need: TOD `libfprint`, the driver `.so`,
firmware in `/var/lib/fprint/.broadcomCv3plusFW`, the udev rules, and the `fprintd` sandbox change.

## Does this apply to my laptop?

```bash
lsusb | grep 0a5c
```

You need one of these IDs:

| USB ID      | Status                      |
|-------------|-----------------------------|
| `0a5c:5865` | **Tested** (see below)      |
| `0a5c:5864` | Listed by Dell's driver, untested |
| `0a5c:5866` | Listed by Dell's driver, untested |
| `0a5c:5867` | Listed by Dell's driver, untested |

Older ControlVault 3 readers (`0a5c:5842`–`5845`) use a *different* driver
(`libfprint-2-tod1-broadcom`) and are **not** covered here.

### Tested on

| | |
|---|---|
| Laptop | Dell Pro 16 Plus PB16250 (BIOS 2.18.1) |
| Reader | Broadcom 58200, `0a5c:5865` |
| OS | Debian 13 (trixie), amd64, kernel 7.2.6 and 7.2.9 |
| Desktop | KDE Plasma 6.3, SDDM |
| Packages | `libfprint-2-2` 1:1.94.9-1, `fprintd` 1.94.5-2 |
| Driver | `libfprint-2-tod1-broadcom-cv3plus` 6.4.372-6.4.062.0, firmware 6.4.062.0 |

## Quick start

```bash
git clone https://github.com/Maarkolo95/dell-cv3plus-fingerprint-debian.git
cd dell-cv3plus-fingerprint-debian

# 1. Install the driver (asks for sudo, builds for ~1-2 minutes)
sudo bash install-fingerprint.sh

# 2. Enroll a finger (no sudo). Press ~11 times, lifting between presses
fprintd-enroll -f right-index-finger

# 3. Check recognition: 5 touches, prints a match score
bash test-fingerprint.sh

# 4. Turn on fingerprint for sudo, login and lock screen
sudo bash enable-fingerprint-auth.sh
```

Then, in a **new** terminal (keep the old one open until it works), run:

```bash
sudo -k && sudo true
```

It should say *"Place your right index finger on the fingerprint reader"*.

> **First run:** the driver may update the reader's firmware. This takes up to a few minutes.
> **Don't power off or suspend** while it runs. The install script waits for it.

## The scripts

| Script | Run as | What it does |
|---|---|---|
| `install-fingerprint.sh` | `sudo` | Checks for the reader, installs build tools, builds TOD `libfprint`, installs Dell's driver and firmware, configures and restarts `fprintd` |
| `enable-fingerprint-auth.sh` | `sudo` | Fingerprint for `sudo`/`su`/SDDM/polkit (3 tries in 20 s, then password) and the KDE lock screen. `--disable` turns it off |
| `test-fingerprint.sh` | user | 5 verification touches, reports how many matched. Optional argument: finger name |
| `uninstall-fingerprint.sh` | `sudo` | Removes everything above and returns to Debian's stock setup |

### What gets installed where

`install-fingerprint.sh` never overwrites files owned by Debian packages:

| Path | What |
|---|---|
| `/usr/local/lib/x86_64-linux-gnu/libfprint-2.so.2*`, `libfprint-2-tod.so.1` | TOD-enabled libfprint, same version as Debian's. Takes priority over `/usr/lib` through the linker search order |
| `/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod-1-broadcom-cv3plus.so` | Dell/Broadcom driver (proprietary) |
| `/var/lib/fprint/.broadcomCv3plusFW/` | Reader firmware (proprietary) |
| `/etc/udev/rules.d/60-libfprint-2-*broadcom-cv3plus.rules` | Device permissions and power management |
| `/etc/systemd/system/fprintd.service.d/broadcom-cv3plus.conf` | Lets `fprintd` write the driver's status files to `/run` and `/var/log`, and disables its idle timeout |
| `/usr/share/doc/libfprint-2-tod1-broadcom-cv3plus/LICENCE.broadcom` | Broadcom's licence |
| `broadcom-controlvault` system user and group | Same as Dell's Ubuntu package |

The installer installs the Debian packages `fprintd`, `libpam-fprintd`, `acl` and the build
dependencies (`meson`, `ninja-build`, `libglib2.0-dev`, `libgusb-dev`, …). It doesn't remove them.

`enable-fingerprint-auth.sh` adds:

| Path | What |
|---|---|
| `/usr/share/pam-configs/fprintd-3tries` | A `pam-auth-update` profile (replaces Debian's 1-try `fprintd` profile) |
| `/etc/pam.d/kde`, `/etc/pam.d/kde-fingerprint` | KDE lock screen: the password and fingerprint checks run side by side |

## Known issues and limitations

- **Only the first enrolled finger is used.** The driver can't search across fingers
  (no "identify" support). `sudo`, login and the lock screen check only the first finger you
  enrolled. Enroll your preferred finger first, or run `fprintd-delete $USER` and start over.
- **"No such device" right after install.** While its firmware updates, the reader reconnects to USB
  several times, and `fprintd` can keep stale copies (`fprintd-list` shows `found 3 devices`). The
  installer detects this and restarts `fprintd`. If you still see it, run `sudo systemctl restart fprintd`.
- **KWallet stays locked after fingerprint login at SDDM.** KWallet needs your password to
  unlock. Unlocking the lock screen with your fingerprint is fine.
- **Debian updates `libfprint-2-2`.** Your `/usr/local` copy keeps being used. If a new
  Debian version breaks `fprintd`, run `install-fingerprint.sh` again: it builds the matching
  `+tod1` version. If no TOD build exists for the new version yet, the script stops with a message.
  In that case, run `uninstall-fingerprint.sh` until one appears.
- **amd64 only.** Broadcom only ships an x86-64 driver.
- **`enroll-remove-and-retry` or `verify-no-match`.** This usually means a partial touch. Press flat, cover the
  whole sensor, and hold about a second. If fewer than 4 of 5 `test-fingerprint.sh` touches
  match, delete the finger and enroll it again, changing the angle slightly between presses.

## Troubleshooting

```bash
fprintd-list $USER                      # is the reader seen? how many devices?
sudo journalctl -u fprintd -n 50        # driver and firmware messages
ldd /usr/libexec/fprintd | grep fprint  # should point to /usr/local/lib/...
cat /run/bcm_fw_status.txt              # firmware update status (empty when no update is running)
```

- `No devices available`: check `lsusb`, then `sudo systemctl restart fprintd`. If a
  firmware update was interrupted, fully **power off** (not reboot), wait 10 s, and power on.
- Fingerprint not working at a `sudo` prompt? Your password still works: after 3 failed
  touches or 20 seconds, `sudo` asks for it as usual.

## Uninstall

```bash
sudo bash uninstall-fingerprint.sh
```

This turns fingerprint authentication off and removes every file listed above. Enrolled prints stay stored on the
chip. Remove them with `fprintd-delete $USER` *before* uninstalling.

## Licence

The scripts in this repository are released under the [MIT licence](LICENSE).

The **Broadcom driver and firmware are proprietary** and are **not** included in this repository.
`install-fingerprint.sh` downloads them at install time from Canonical's OEM repository
(pinned to commit `0614543a`). By installing them you accept Broadcom's licence, which the installer
copies to `/usr/share/doc/libfprint-2-tod1-broadcom-cv3plus/LICENCE.broadcom`.

This project isn't affiliated with or endorsed by Dell, Broadcom, Canonical or Debian. It flashes
reader firmware and changes your system's authentication setup. Use it at your own risk.

## Search keywords

Dell ControlVault 3 Plus Linux · CV3+ fingerprint · Broadcom 58200 Linux driver · BCM58200 ·
0a5c:5865 · 0a5c:5864 · 0a5c:5866 · 0a5c:5867 · Dell Pro 16 Plus fingerprint Linux ·
Dell Pro 14 Plus · Dell Pro 13 Plus · Dell Pro Max · Latitude 7450 / 5450 / 7350 fingerprint Linux ·
Precision 3490 / 5490 fingerprint · Debian 13 trixie fingerprint reader · fprintd No devices available ·
libfprint TOD · libfprint-2-tod1-broadcom-cv3plus on Debian · fingerprint sudo Debian ·
pam_fprintd · SDDM fingerprint login · KDE Plasma 6 lock screen fingerprint (kde-fingerprint) ·
Intel Lunar Lake / Core Ultra 200V laptop fingerprint Linux

## Sources

- Dell CV3 Plus driver packaging (Canonical OEM):
  <https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/libfprint-2-tod1-broadcom-cv3plus>
- Ubuntu packaging bug: <https://bugs.launchpad.net/ubuntu/+bug/2099289>
- libfprint with TOD support: <https://gitlab.freedesktop.org/3v1n0/libfprint>
- Similar guide for the older ControlVault 3 (`0a5c:5843`) on Debian 13:
  <https://dev.to/fquinto/getting-the-broadcom-controlvault-3-fingerprint-reader-0a5c5843-working-on-debian-13-44ld>
