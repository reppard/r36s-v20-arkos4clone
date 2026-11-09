# ArkOS4Clone on the R36S-V20 (RF3536K3KA board)

Get [ArkOS4Clone / dArkOS4Clone](https://github.com/lcdyk0517/arkos4clone) running on the R36S clone labelled **R36S-V20 2025-05-18 2549**, with the **RF3536K3KA** board.

On this board every option in the stock arkos4clone DTB selector boots to a blank screen with only the backlight on. This repo bundles the files the device needs and a script that applies them to a freshly flashed card.

## Is this my device?

Check the BOOT partition of the card that came with the device. It should look like this:

- `rf3536k3ka.dtb`
- `extlinux/extlinux.conf`
- `Image` (kernel `5.10.160`)

If your stock card has a `boot.ini` instead, this repo is not for you. Use the normal [arkos4clone instructions](https://github.com/lcdyk0517/arkos4clone/wiki).

## Requirements

- macOS (the script uses `diskutil`)
- A microSD card (16 GB or larger)
- A tool to extract `.7z` and `.xz` files, such as [7-Zip](https://www.7-zip.org/) (`brew install sevenzip`) or The Unarchiver
- A flashing tool: [balenaEtcher](https://etcher.balena.io/), [Raspberry Pi Imager](https://www.raspberrypi.com/software/) (choose "Use custom"), or `dd`

## Steps

### 1. Download the image

Download the `ArkOS4Clone-*` or `dArkOS4Clone-*` image from the **[arkos4clone releases page](https://github.com/lcdyk0517/arkos4clone/releases)**.

This was tested with **[ArkOS4Clone-20261008 and dArkOS4Clone-20261008](https://github.com/lcdyk0517/arkos4clone/releases/tag/20261008)**. dArkOS is the better choice: newer PortMaster ports such as Cuphead need its newer glibc.

The image is split into parts (`.7z.001`, `.7z.002`, ...). Download every part into the same folder, then extract the first one. That gives you a `.img.xz` file, which you extract again to get the `.img`.

```sh
7zz x ArkOS4Clone-20261008.img.xz.7z.001
xz -dk ArkOS4Clone-20261008.img.xz
```

### 2. Flash the image

Flash the `.img` to the microSD card with balenaEtcher or Raspberry Pi Imager. When it's done, unplug the card and plug it back in so BOOT mounts.

### 3. Select the device in the DTB selector

Run the DTB selector from the card's BOOT partition (`dtb_selector_macos`) and pick **Clone R36s → Clone Type 1 Panel 2**.

The battery and overclock answers don't matter: the script always sets the `arkos4clone` battery driver (the Rockchip one reads 0%) and removes any overclock.

### 4. Run the script

Find the card's disk number:

```sh
diskutil list external physical
```

Then run the script, replacing `disk8` with your card's number:

```sh
./prepare_card.sh disk8
```

It asks for your password once, for the bootloader write. Check the disk number carefully: the script writes raw sectors to that disk.

### 5. Boot

Put the card in the device and power it on. First boot repartitions the card, installs the GPU driver and reboots by itself, possibly more than once. After that, EmulationStation starts.

## What the script does

1. **Checks:** it refuses internal disks and checks the bootloader dump. It also checks that BOOT starts after the bootloader area and that `boot.ini` loads the type1 panel2 DTB.
2. **Kernel:** copies the arkos4clone **5.10** kernel (`files/Image`) to BOOT.
3. **DTB:** copies the **clone type1 panel2 5.10 DTB with the DMC disabled** (`files/rk3326-r36s-type1-panel2-linux.dtb`) to BOOT.
4. **`extlinux/extlinux.conf`:** writes it with the boot arguments from `boot.ini`, minus any overclock, plus `rk817_gauge=arkos4clone` for the battery.
5. **GPU driver:** if the image is older than arkos4clone's 5.10 support, it adds `files/fix510/` to BOOT and hooks it into `clone.sh`. On first boot it installs the 5.10 modules, the `g29p1` Mali driver, `mali-select` and the Vulkan files, then deletes itself. The log is in `BOOT/fix510.log`.
6. **Bootloader:** writes `files/open_boot16M.bin` to sectors 64–32767. That's the idbloader at sector 64, U-Boot at 16384 and trust at 24576. The partition table in sector 0 is left alone. Every part is built from Rockchip's public sources and binaries. No vendor dump is needed (see [Rebuilding the bootloader](#rebuilding-the-bootloader)).

## Why each piece is needed

| Problem | Cause | Fix |
|---|---|---|
| Blank screen, backlight on, with every DTB | The chip is an **RK3326S** (PX30S). The arkos4clone U-Boot (Hardkernel ODROID-GO fork) has no PX30S support, so it never starts Linux. | Rockchip's `next-dev` U-Boot, which supports PX30S |
| Rockchip U-Boot ignores `boot.ini` | It boots through `extlinux`, like the stock card | `extlinux/extlinux.conf` |
| Completely dead with a 4.4 DTB | This U-Boot sets up the power chip and display from the kernel DTB, and a 4.4-style DTB stops it before it turns on the backlight | The 5.10 kernel and DTB only |
| Boot hangs in `rockchip-dmc`, then `rk3x-i2c ff180000.i2c: timeout` spam | Changing RAM speed through the firmware breaks things. The stock DTB keeps the RAM fixed at 528 MHz. | `/dmc` disabled in the DTB |
| `mali ... stride 48 passed to job_submit isn't supported` | Release `20261008` came out before arkos4clone's 5.10 support, so it has the 4.4 GPU driver (`rxp0`) | `files/fix510` payload |

The panel, timings, reset and power GPIOs, buttons, sticks and headphone detect all match **clone type1 panel2**. The "R36S-V20" DTB in [southoz/dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36/tree/main/files/BOOT/dtb/clone/R36S-V20%202025-05-18%202549) is not for this unit: it has the panel1 init sequence.

## Don'ts

- **Don't install arkos4clone OTA updates** (`update-*.tar` in `/roms`). Their installer deletes `Image` and the DTBs from BOOT and writes the arkos4clone bootloader back, which brings the blank screen back. To update, flash a new release and run the script again.
- **Don't switch kernels** with `switch-kernel` or the DTB selector's kernel option. The 4.4 kernel can't boot with this bootloader.
- **If you re-run the DTB selector, re-run this script afterwards.** The selector replaces the patched DTB.

## Using your stock card's bootloader instead

The bundled bootloader works without a stock card. To use the one from your own stock card instead:

```sh
diskutil list
diskutil unmountDisk /dev/diskN
sudo dd if=/dev/rdiskN of="$HOME/stock_boot16M.bin" bs=512 count=32768
diskutil eject /dev/diskN
./prepare_card.sh disk8 "$HOME/stock_boot16M.bin"
```

Here `diskN` is the stock card and `disk8` is the new one. **Keep the stock card**, or an image of it, as a backup.

## Troubleshooting

To see kernel messages on screen, replace ` quiet splash` with ` loglevel=7 console=tty0` in `BOOT/extlinux/extlinux.conf`.

| What you see | Look at |
|---|---|
| No backlight at all | The bootloader write, or a 4.4 DTB on BOOT |
| Hang at `rockchip-dmc` or I2C timeouts | `fdtget BOOT/rk3326-r36s-type1-panel2-linux.dtb /dmc status` should print `disabled` |
| Mali `stride 48` spam | `BOOT/fix510.log` |

## Where the files come from

| File | Source |
|---|---|
| `files/Image` | `boot/dArkOS/consoles/kernel/5.10/Image` from [arkos4clone `0e7d606`](https://github.com/lcdyk0517/arkos4clone/tree/0e7d6060cfccae3b87d3b26688b051e5829ff78e) (`5.10.252-arkos4clone`, built from jokubasver/rockchip-kernel `arkos4clone-5.10` `c1c445bcb40a`) |
| `files/rk3326-r36s-type1-panel2-linux.dtb` | `boot/dArkOS/consoles/clone type1 panel2/5.10/` at the same commit, with `fdtput -t s <dtb> /dmc status disabled` applied |
| `files/fix510/payload.tar.xz` | `git archive` of the 5.10 modules, Mali `g29p1`, `mali-select`, Vulkan files and udev rule from `rootfs/dArkOS` and `rootfs/ArkOS` at the same commit |
| `files/open_boot16M.bin` | Built from public Rockchip sources, see below |

## Rebuilding the bootloader

`files/open_boot16M.bin` (sha256 `4f5d63a2…addd2a`) is zeros except for three parts:

| Sector | Part | Built from |
|---|---|---|
| 64 | idbloader (174972 bytes) | [rkbin `174394f`](https://github.com/rockchip-linux/rkbin/tree/174394f452cac8f8da6aef4761f68fc7b49cd5d0/bin/rk33) `px30_ddr_333MHz_v2.08.bin` with the debug UART set to UART5, plus `rk3326_miniloader_v1.35.bin`. Byte-identical to the stock card's idbloader. |
| 16384 | `uboot.img` | [rockchip-linux/u-boot `next-dev` `1c535d6`](https://github.com/rockchip-linux/u-boot/tree/1c535d65b8509f388d09e49fb6961f49fda35a1d), `rk3326_defconfig` |
| 24576 | `trust.img` | [rkbin `3e288fe`](https://github.com/rockchip-linux/rkbin/tree/3e288fe814e059dd06833495f845cab04ac20a5c) `RKTRUST/RK3326TRUST.ini` (BL31 v1.37, BL32 v2.21) |

idbloader (rkbin `174394f`'s `tools/ddrbin_tool` sets the UART, `tools/mkidb.py` packs the image):

```sh
cp tools/ddrbin_param.txt param.txt
sed -i 's/^uart id=$/uart id=5/; s/^uart iomux=$/uart iomux=0/; s/^uart baudrate=$/uart baudrate=1500000/' param.txt
cp bin/rk33/px30_ddr_333MHz_v2.08.bin ddr.bin
python3 tools/ddrbin_tool.py px30 param.txt ddr.bin
python3 mkidb.py ddr.bin bin/rk33/rk3326_miniloader_v1.35.bin idbloader.img
```

`uboot.img` and `trust.img`, with `rkbin` (`3e288fe`) checked out next to `u-boot`. The rkbin packing tools are x86-64 Linux binaries:

```sh
docker run --rm --platform linux/amd64 -v "$PWD":/w -w /w/u-boot ubuntu:20.04 bash -c '
apt-get update && apt-get install -y make gcc gcc-aarch64-linux-gnu bc bison flex python3 python-is-python3 device-tree-compiler libssl-dev git file gawk
git config --global --add safe.directory "*"
./make.sh rk3326 CROSS_COMPILE=/usr/bin/aarch64-linux-gnu-'
```

Assemble:

```sh
dd if=/dev/zero of=open_boot16M.bin bs=1m count=16
dd if=idbloader.img of=open_boot16M.bin bs=512 seek=64 conv=notrunc
dd if=u-boot/uboot.img of=open_boot16M.bin bs=512 seek=16384 conv=notrunc
dd if=u-boot/trust.img of=open_boot16M.bin bs=512 seek=24576 conv=notrunc
```

All credit for (d)ArkOS4Clone goes to [lcdyk0517/arkos4clone](https://github.com/lcdyk0517/arkos4clone) and its contributors.
