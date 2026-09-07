# UART extraction plan — EWS377AP v3

What to grab off a live unit the moment you have UART hooked up. Goal: pull the full hardware
description (DTB, WiFi board data, per-device caldata, GPIO/LED/switch topology) so the OpenWrt
device tree and board files can be written from real data instead of guesses.

Most of the *generic* data (DTB, `board-2.bin`) is also extractable from the firmware image offline.
**The one thing that requires the physical unit is per-device ART/caldata + the real MAC/serial** —
which is exactly why UART matters.

> **STATUS: done (2026-09-06).** UART was connected (header J2, 115200 8N1); DTB, board data,
> per-device ART/caldata, the full partition table, and the u-boot env were all extracted, and the
> port is now validated on hardware. Kept as the extraction-method reference.

---

## 0. Wiring (do this once)

- **USB-TTL adapter set to 3.3V** (never 5V — you'll fry the SoC UART).
- Header **J2** on the v3 PCB. Pinout as identified: **GND / TX / RX** (VCC unused).
- Connections:
  - adapter **GND ↔ AP GND**
  - adapter **RX ↔ AP TX**
  - adapter **TX ↔ AP RX**
  - **do NOT wire VCC** — the AP is self-powered by PoE.
- Terminal: **115200 8N1**, no flow control. e.g. `screen /dev/tty.usbserial-XXXX 115200`
  or `picocom -b 115200 /dev/tty.usbserial-XXXX`.

---

## 1. First: the go/no-go (secure boot)

Power on, press a key during `bootdelay=5` to stop at the u-boot prompt.

```
printenv                         # capture the FULL env — see if bootipq is complete
                                 # look for secure_boot / sec_auth / anti-rollback flags
# non-destructive unsigned-boot test (proves secure boot is NOT enforced):
tftpboot 0x44000000 openwrt-initramfs.itb
bootm 0x44000000
```

If an unsigned FIT boots → secure boot open → green light for the whole port.

---

## 2. Back up the irreplaceable partitions BEFORE anything else

From a booted OS shell (stock EWS firmware: `ssh -p 8822 root@<ip>`, pw `admin`; or the u-boot/TFTP
route). **ART corruption is a real brick — back it up first.**

```
# identify partitions
cat /proc/mtd

# dump the ones that matter (adjust mtdN to /proc/mtd names on THIS unit):
dd if=/dev/mtd11 of=/tmp/ART.bin          # calibration + MAC — MOST IMPORTANT
dd if=/dev/mtd7  of=/tmp/APPSBLENV.bin     # u-boot env
dd if=/dev/mtd8  of=/tmp/APPSBL.bin        # bootloader defaults
dd if=/dev/mtd3  of=/tmp/DEVCFG.bin        # device config
# copy them all off the unit immediately (scp/tftp) and checksum.
```

Also stash a pristine stock `.bin` for each slot so you can always flash back.

---

## 3. Harvest the hardware description

```
# device tree (the single biggest artifact):
cp /sys/firmware/fdt /tmp/hk07.dtb
# if /sys/firmware/fdt is absent, pull the DTB from the kernel/boot partition instead.

# WiFi board data + regdb:
tar czf /tmp/wifi-fw.tgz /lib/firmware/IPQ8074    # board-2.bin, bdwlan*, regulatory

# GPIO / LED map:
ls -l /sys/class/leds/                            # LED names → function
cat /sys/kernel/debug/gpio 2>/dev/null            # GPIO usage (if debugfs mounted)

# ethernet / switch topology:
ssdk_sh sw dump 2>/dev/null || swconfig dev switch0 show

# OEM uci config (PHY addrs, port roles, wifi cal path):
tar czf /tmp/oem-config.tgz /etc/config /etc/board.json 2>/dev/null

# board / model identity:
cat /etc/modelname /proc/device-tree/model 2>/dev/null
```

Copy `/tmp/hk07.dtb`, `wifi-fw.tgz`, `oem-config.tgz`, and the switch/GPIO dumps off the unit.

---

## 4. Record real identity (per-device, do NOT publish real values)

```
fw_printenv | grep -Ei 'ethaddr|sn|snextra|serial'   # or: setconfig -g 0 ; setconfig -g 19
# real MAC lives in ART (mtd11); u-boot env ethaddr may differ.
```

Note these privately (real MAC / serial). They're needed to re-register / restore identity but must
**not** go in a public repo.

---

## 5. Decompile + commit artifacts

On the workstation:

```
dtc -I dtb -O dts -o hk07-oem.dts hk07.dtb
```

Commit (to `artifacts/`, a **private** repo): `hk07-oem.dts`, the `/lib/firmware/IPQ8074` tree, the
switch/GPIO/uci dumps, and the partition backups' **checksums** (not the ART/env blobs themselves if
they carry per-device secrets/MAC).

---

## Gotchas (learned the hard way)

- **Never hand-rebuild a partial u-boot env.** A valid-but-incomplete env makes `bootipq` fail; an
  *erased* env is safer (u-boot falls back to full compiled defaults in APPSBL). Recovery from a bad
  env: `env default -a; saveenv; reset`.
- Wiping the env also wipes `ethaddr` → the OS falls back to a **default MAC** (`00:03:7f:12:3e:87`)
  and the unit reappears on a **different DHCP IP** — it looks bricked but isn't. Check DHCP leases /
  the PoE switch port before assuming a brick.
- Stock EWS firmware exposes SSH on **port 8822** (not 22); telnet(23) is a restricted CLI only.
- A clock-skewed unit (env wipe resets time) fails cloud check-in with a distinct timestamp error —
  unrelated to firmware validity, but worth knowing when debugging.
