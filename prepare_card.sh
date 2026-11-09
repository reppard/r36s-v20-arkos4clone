#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: ./prepare_card.sh <disk> [boot16M.bin]

Prepares a freshly flashed (d)ArkOS4Clone card for the R36S-V20 clone
(RF3536K3KA board) on macOS. Run dtb_selector first and pick
"Clone Type 1 Panel 2". See README.md.
EOF
  exit 1
}

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -eq 1 || $# -eq 2 ]] || usage
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FILES="$HERE/files"
DISK=${1#/dev/}
BLOB=${2:-$FILES/open_boot16M.bin}
DTB=rk3326-r36s-type1-panel2-linux.dtb

[[ "$(uname)" == Darwin ]] || die "this script uses diskutil and runs on macOS only"
[[ "$DISK" =~ ^disk[0-9]+$ ]] || die "disk must look like disk8"
[[ -f "$BLOB" ]] || die "$BLOB not found"

diskutil info "$DISK" | grep -qE "Removable Media: +(Removable|Yes)|Device Location: +External" ||
  die "$DISK is not a removable/external disk"

[[ $(stat -f%z "$BLOB") -eq 16777216 ]] || die "$BLOB is not a 16 MiB bootloader image"
[[ $(dd if="$BLOB" bs=1 skip=$((16384*512)) count=8 2>/dev/null) == "LOADER  " ]] || die "$BLOB has no U-Boot at sector 16384"
[[ $(dd if="$BLOB" bs=1 skip=$((24576*512)) count=4 2>/dev/null) == "BL3X" ]] || die "$BLOB has no trust at sector 24576"

OFFSET=$(diskutil info "${DISK}s1" | awk -F': *' '/Partition Offset/{print $2+0}')
[[ "$OFFSET" -ge 16777216 ]] || die "${DISK}s1 starts at $OFFSET, inside the bootloader area"

BOOT=$(diskutil info "${DISK}s1" | awk -F': *' '/Mount Point/{print $2}')
[[ -n "$BOOT" && -f "$BOOT/boot.ini" ]] || die "${DISK}s1 is not a mounted (d)ArkOS BOOT partition"
grep -q "^load .*$DTB" "$BOOT/boot.ini" || die "boot.ini does not load $DTB: run dtb_selector and pick Clone Type 1 Panel 2"

BOOTARGS=$(sed -n 's/^setenv bootargs "\(.*\)"/\1/p' "$BOOT/boot.ini" | tr -d '\r')
[[ -n "$BOOTARGS" ]] || die "no bootargs in boot.ini"

echo "== kernel + DTB"
cp -X "$FILES/Image" "$BOOT/Image"
cp -X "$FILES/$DTB" "$BOOT/$DTB"

echo "== extlinux.conf"
mkdir -p "$BOOT/extlinux"
cat > "$BOOT/extlinux/extlinux.conf" <<EOF
LABEL ArkOS4Clone
  LINUX /Image
  FDT /$DTB
  INITRD /uInitrd
  APPEND $BOOTARGS
EOF

if [[ -f "$BOOT/consoles/kernel/5.10/Image" ]]; then
  echo "== image already ships 5.10 userspace, no GPU payload needed"
else
  echo "== 5.10 GPU/modules payload"
  mkdir -p "$BOOT/fix510"
  cp -X "$FILES/fix510/payload.tar.xz" "$FILES/fix510/install.sh" "$BOOT/fix510/"

  HOOK='[[ -f /boot/fix510/install.sh ]] && bash /boot/fix510/install.sh >> /boot/fix510.log 2>&1'
  TARGET="$BOOT/clone.sh"
  [[ -f "$TARGET" ]] || TARGET="$BOOT/firstboot.sh"
  grep -q "EUID -ne 0" "$TARGET" || die "$TARGET is not clone.sh"
  if ! grep -qF "$HOOK" "$TARGET"; then
    awk -v hook="$HOOK" '/EUID -ne 0/{f=1} f && $0=="fi"{print; print hook; f=0; next} {print}' "$TARGET" > "$TARGET.new"
    grep -qF "$HOOK" "$TARGET.new" || die "could not hook $TARGET"
    bash -n "$TARGET.new" || die "hooked $TARGET has a syntax error"
    mv "$TARGET.new" "$TARGET"
  fi
fi

find "$BOOT" -maxdepth 2 -name '._*' -delete 2>/dev/null || true
sync

echo "== bootloader -> /dev/r$DISK sectors 64-32767 (sudo)"
diskutil unmountDisk "$DISK"
sudo dd if="$BLOB" of="/dev/r$DISK" bs=512 skip=64 seek=64 count=32704
sync
diskutil eject "$DISK"
echo "Done. Put the card in the device and boot it."
