#!/bin/bash
# Fingerprint support for the Dell ControlVault 3 Plus reader
# (Broadcom 58200, USB 0a5c:5864/5865/5866/5867) on Debian 13 (trixie), amd64.
#
# Run with:  sudo bash install-fingerprint.sh
# Undo with: sudo bash uninstall-fingerprint.sh
#
# What it does:
#  1. Installs build tools.
#  2. Builds libfprint (same version as Debian's) with "TOD" plug-in support, which
#     Dell's proprietary driver needs. It goes to /usr/local, so Debian's own files
#     are left untouched.
#  3. Downloads Dell/Broadcom's CV3 Plus driver + firmware from Canonical's OEM repo
#     (pinned to a tested commit) and installs it.
#  4. Lets fprintd write the driver's status files, restarts it, and waits for the reader.
set -euo pipefail

# Tested driver version (6.4.372-6.4.062.0). Override: CV3_COMMIT=<sha> sudo -E bash ...
CV3_REPO=https://git.launchpad.net/~oem-solutions-engineers/pc-enablement/+git/libfprint-2-tod1-broadcom-cv3plus
CV3_COMMIT=${CV3_COMMIT:-0614543a2a72d1fc1cad0af924741f62b848afab}
LIBFPRINT_REPO=https://gitlab.freedesktop.org/3v1n0/libfprint.git
SUPPORTED_IDS="5864 5865 5866 5867"
SYS_LIB=/usr/lib/x86_64-linux-gnu
LOCAL_LIB=/usr/local/lib/x86_64-linux-gnu

die() { echo "ERROR: $*" >&2; exit 1; }

# ---------- checks ----------
[ "$(id -u)" -eq 0 ] || die "Please run with: sudo bash $0"
USER_NAME=${SUDO_USER:-}
[ -n "$USER_NAME" ] && [ "$USER_NAME" != root ] || die "Run via sudo from your normal user account."
[ "$(dpkg --print-architecture)" = amd64 ] || die "Only amd64 is supported (Broadcom ships an x86-64 driver only)."

FOUND_ID=""
for id in $SUPPORTED_IDS; do
  lsusb -d "0a5c:$id" >/dev/null 2>&1 && FOUND_ID=$id
done
if [ -z "$FOUND_ID" ]; then
  echo "WARNING: no ControlVault 3 Plus reader (0a5c:5864-5867) found on USB."
  echo "         lsusb shows: $(lsusb | grep -i 0a5c || echo 'no Broadcom devices')"
  read -r -p "Continue anyway? [y/N] " a; [ "$a" = y ] || [ "$a" = Y ] || exit 1
else
  echo "Found reader 0a5c:$FOUND_ID"
fi

echo "==> [1/5] Installing fprintd and build tools"
apt-get update -q
apt-get install -y -q fprintd libpam-fprintd acl git build-essential meson ninja-build pkg-config \
  libglib2.0-dev libgusb-dev libgudev-1.0-dev libpixman-1-dev libssl-dev libcairo2-dev

LIBVER=$(dpkg-query -W -f='${Version}' libfprint-2-2 | sed 's/^[0-9]*://; s/-.*//')
TAG="v${LIBVER}+tod1"
rc=0; git ls-remote --exit-code --tags "$LIBFPRINT_REPO" "refs/tags/$TAG" >/dev/null || rc=$?
[ "$rc" -eq 2 ] && die "No TOD build ($TAG) exists for Debian's libfprint $LIBVER yet. See README."
[ "$rc" -eq 0 ] || die "Could not reach $LIBFPRINT_REPO (network problem?). Try again."

echo "==> [2/5] Building libfprint $TAG (as $USER_NAME)"
BUILD=$(runuser -u "$USER_NAME" -- mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
runuser -u "$USER_NAME" -- bash -euo pipefail -c "
  cd '$BUILD'
  git clone -q -c advice.detachedHead=false --depth=1 --branch '$TAG' '$LIBFPRINT_REPO' libfprint
  mkdir cv3plus && cd cv3plus && git init -q
  git fetch -q --depth=1 '$CV3_REPO' '$CV3_COMMIT' && git -c advice.detachedHead=false checkout -q FETCH_HEAD
  cd ../libfprint
  sed -i -e \"/subdir('tests')/s/^/#/\" -e \"/subdir('examples')/s/^/#/\" meson.build
  meson setup build --prefix=/usr --libdir=lib/x86_64-linux-gnu \
    -Ddoc=false -Dintrospection=false -Dudev_rules=disabled -Dudev_hwdb=disabled \
    -Dinstalled-tests=false -Dgtk-examples=false
  meson compile -C build
  meson install -C build --destdir '$BUILD/stage' >/dev/null
"

echo "==> [3/5] Installing TOD-enabled libfprint into $LOCAL_LIB"
mkdir -p "$LOCAL_LIB"
cp -a "$BUILD"/stage/usr/lib/x86_64-linux-gnu/libfprint-2.so.2* "$LOCAL_LIB"/
cp -a "$BUILD"/stage/usr/lib/x86_64-linux-gnu/libfprint-2-tod.so.1* "$LOCAL_LIB"/
# Built as the normal user, so hand ownership to root (fprintd runs as root and loads these).
chown -h root:root "$LOCAL_LIB"/libfprint-2.so.2* "$LOCAL_LIB"/libfprint-2-tod.so.1*
ldconfig

echo "==> [4/5] Installing Broadcom CV3 Plus driver and firmware"
CV="$BUILD/cv3plus"
install -Dm644 "$CV"/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod-1-broadcom-cv3plus.so \
  "$SYS_LIB"/libfprint-2/tod-1/libfprint-2-tod-1-broadcom-cv3plus.so
install -Dm644 "$CV"/lib/udev/rules.d/60-libfprint-2-device-broadcom-cv3plus.rules \
  /etc/udev/rules.d/60-libfprint-2-device-broadcom-cv3plus.rules
install -Dm644 "$CV"/debian/udev /etc/udev/rules.d/60-libfprint-2-tod1-broadcom-cv3plus.rules
mkdir -p /var/lib/fprint
rm -rf /var/lib/fprint/.broadcomCv3plusFW
cp -r "$CV"/var/lib/fprint/.broadcomCv3plusFW /var/lib/fprint/
chmod 644 /var/lib/fprint/.broadcomCv3plusFW/*
install -Dm644 "$CV"/LICENCE.broadcom /usr/share/doc/libfprint-2-tod1-broadcom-cv3plus/LICENCE.broadcom
getent group broadcom-controlvault >/dev/null || addgroup --system broadcom-controlvault
getent passwd broadcom-controlvault >/dev/null || adduser --system --no-create-home \
  --home /nonexistent --disabled-password --ingroup broadcom-controlvault broadcom-controlvault

echo "==> [5/5] Configuring and restarting fprintd"
# The driver writes status files to /run and /var/log; fprintd's sandbox blocks that by default.
# --no-timeout keeps fprintd alive during the first-run firmware update (can take minutes).
mkdir -p /etc/systemd/system/fprintd.service.d
cat > /etc/systemd/system/fprintd.service.d/broadcom-cv3plus.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/libexec/fprintd --no-timeout
ReadWritePaths=/run /var/log
EOF
udevadm control --reload-rules
udevadm trigger --type=devices --subsystem-match=usb --attr-match=idVendor=0a5c || true
systemctl daemon-reload
systemctl restart fprintd

echo
echo "fprintd now uses: $(ldd /usr/libexec/fprintd | grep -o '/[^ ]*libfprint-2.so.2')"
echo "Waiting for the reader (a firmware update may run on first start; do NOT power off)..."

list() { runuser -u "$USER_NAME" -- fprintd-list "$USER_NAME" 2>/dev/null || true; }
device_count() { list | sed -n 's/^found \([0-9]*\) devices*/\1/p'; }

for i in $(seq 1 36); do
  if list | grep -q 'Fingerprints for user\|has no fingers enrolled'; then
    # The chip reconnects several times during a firmware update; fprintd can keep
    # stale copies of it ("found 3 devices") that fail with "No such device".
    if [ "$(device_count)" != 1 ]; then
      echo; echo "Reader re-connected during firmware update; restarting fprintd..."
      sleep 5; systemctl restart fprintd; sleep 5
    fi
    echo; echo "SUCCESS: reader detected."
    list
    echo
    echo "Next: enroll a finger (as your normal user, no sudo):  fprintd-enroll -f right-index-finger"
    exit 0
  fi
  sleep 5; echo -n "."
done
echo
echo "Reader not ready yet. Recent fprintd log:"
journalctl -u fprintd --no-pager -n 30 || true
echo
echo "If a firmware update ran, try: sudo systemctl restart fprintd ; then fprintd-list $USER_NAME"
echo "If it still fails, fully power off (not reboot), wait 10s, power on."
exit 1
