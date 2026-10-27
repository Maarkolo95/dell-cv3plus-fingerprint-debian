#!/bin/bash
# Turn on fingerprint authentication for sudo, su, SDDM login, polkit prompts and the
# KDE Plasma lock screen. Your password always keeps working as a fallback.
#
# Run with:  sudo bash enable-fingerprint-auth.sh
# Undo with: sudo bash enable-fingerprint-auth.sh --disable
#
# Settings: 3 fingerprint tries within 20 s, then the password prompt.
# (Debian's stock profile allows only 1 try in 10 s, which fails too easily.)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Please run with: sudo bash $0"; exit 1; }

PROFILE=/usr/share/pam-configs/fprintd-3tries

if [ "${1:-}" = "--disable" ]; then
  [ -f "$PROFILE" ] && pam-auth-update --disable fprintd-3tries
  pam-auth-update --disable fprintd
  rm -f "$PROFILE" /etc/pam.d/kde-fingerprint /etc/pam.d/kde
  echo "Fingerprint authentication turned off (password only)."
  exit 0
fi

[ -f /usr/lib/x86_64-linux-gnu/security/pam_fprintd.so ] \
  || { echo "libpam-fprintd is missing. Run install-fingerprint.sh first."; exit 1; }

# 1) sudo, su, SDDM, polkit, console login: a local pam-auth-update profile, so Debian
#    package updates don't reset it. It replaces (conflicts with) the stock "fprintd" one.
cat > "$PROFILE" <<'EOF'
Name: Fingerprint authentication (3 tries, local)
Default: no
Priority: 260
Conflicts: fprintd
Auth-Type: Primary
Auth:
	[success=end default=ignore]	pam_fprintd.so max-tries=3 timeout=20
EOF
pam-auth-update --disable fprintd
pam-auth-update --enable fprintd-3tries

# 2) KDE lock screen. The greeter runs "kde" (password) and "kde-fingerprint" side by side.
#    Keep "kde" password-only so typing a password is never blocked waiting for a finger.
cat > /etc/pam.d/kde <<'EOF'
# KDE lock screen: password check only (fingerprint is handled by kde-fingerprint).
auth    required    pam_unix.so nullok
@include common-account
EOF
cat > /etc/pam.d/kde-fingerprint <<'EOF'
# KDE lock screen: fingerprint unlock, runs alongside the password field.
auth    required    pam_fprintd.so
@include common-account
EOF
chmod 644 /etc/pam.d/kde /etc/pam.d/kde-fingerprint

echo
echo "Done. Fingerprint line in /etc/pam.d/common-auth:"
grep -n pam_fprintd /etc/pam.d/common-auth
echo
echo "Test it in a NEW terminal (keep this one open until it works):  sudo -k && sudo true"
