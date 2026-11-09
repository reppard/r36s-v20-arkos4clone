#!/bin/bash
set -eux
P=/boot/fix510/payload.tar.xz
X="tar -xJf $P -C / --strip-components=2 --no-same-owner --no-overwrite-dir"
$X rootfs/dArkOS
grep -q dArkOS /usr/share/plymouth/themes/text.plymouth || $X rootfs/ArkOS
E=/etc/emulationstation
for v in sd1 sd2 dual; do
  if [[ -f $E/es_systems.$v && ! -f $E/es_systems.cfg.$v ]]; then cp $E/es_systems.$v $E/es_systems.cfg.$v; fi
done
chmod 755 /usr/local/sbin/mali-select
depmod -a 5.10.252-arkos4clone
/usr/local/sbin/mali-select
rm -rf /boot/fix510
sync
