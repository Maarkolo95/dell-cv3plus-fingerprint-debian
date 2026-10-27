#!/bin/bash
# Undo install-fingerprint.sh (and enable-fingerprint-auth.sh) and go back to
# Debian's stock libfprint. Run with:  sudo bash uninstall-fingerprint.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Please run with: sudo bash $0"; exit 1; }

# Turn fingerprint login off first, so nothing waits for a reader that's going away.
if [ -f /usr/share/pam-configs/fprintd-3tries ]; then
  pam-auth-update --disable fprintd-3tries
  rm -f /usr/share/pam-configs/fprintd-3tries
fi
pam-auth-update --disable fprintd
rm -f /etc/pam.d/kde /etc/pam.d/kde-fingerprint

rm -f /usr/local/lib/x86_64-linux-gnu/libfprint-2.so.2* /usr/local/lib/x86_64-linux-gnu/libfprint-2-tod.so.1*
rm -f /usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod-1-broadcom-cv3plus.so
rmdir /usr/lib/x86_64-linux-gnu/libfprint-2/tod-1 2>/dev/null || true
rmdir /usr/lib/x86_64-linux-gnu/libfprint-2 2>/dev/null || true
rm -f /etc/udev/rules.d/60-libfprint-2-device-broadcom-cv3plus.rules \
      /etc/udev/rules.d/60-libfprint-2-tod1-broadcom-cv3plus.rules
rm -rf /var/lib/fprint/.broadcomCv3plusFW /usr/share/doc/libfprint-2-tod1-broadcom-cv3plus
rm -f /etc/systemd/system/fprintd.service.d/broadcom-cv3plus.conf
rmdir /etc/systemd/system/fprintd.service.d 2>/dev/null || true

ldconfig
udevadm control --reload-rules
systemctl daemon-reload
systemctl restart fprintd || true
echo "Removed. Debian's stock libfprint is active again; password-only authentication."
echo "(Enrolled fingerprints stay stored on the ControlVault chip.)"
