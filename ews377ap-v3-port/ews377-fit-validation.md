> Mirror of the report in the firmware repo: https://github.com/ParkWardRR/openwrt-engenius-ews377ap-ecw230-ews377fit/blob/main/docs/ews377-fit-hardware-validation.md

# EWS377-FIT — hardware validation report

**Date:** 2026-10-06 · **Firmware:** OpenWrt SNAPSHOT (`openwrt-nss-edma` @ `ews377ap-v3` branch, kernel 6.18.44) ·
**Result: PASS** — OpenWrt boots, persists from NAND, and runs ethernet, both radios and sysupgrade on a real
EnGenius **EWS377-FIT** (product_id 300). Three board-support problems were found and fixed along the way (see
[Findings](#findings)). A few checklist items are still untested (see [Not yet tested](#not-yet-tested)).

This unit is a **hardware/bootloader variant we had not seen before**: it differs from the documented EWS377AP v3
unit in RAM size, bootloader build, and where the MAC address lives. Details below. Device-unique values (serial
number, full MAC, cloud certificate) are intentionally omitted from this report.

## Unit under test

| Item | EWS377-FIT unit | Documented EWS377AP v3 unit |
|---|---|---|
| SoC / board | IPQ8074 (`AP-HK07`), machid `0x8010006` | same |
| Stock OS | OEM OpenWrt 4.4.60 (`config@hk07` FIT) | OEM |
| **RAM** | **512 MiB** (DDR4) | 1 GiB |
| NAND | 256 MiB Macronix MX30UF2G18AC, 128 KiB blocks, 1 factory-bad block | same |
| **u-boot** | **2016.01 `EWS377AP-FIT` V2.1.0 (2022-07-01)** | 2.0.0 |
| Boot flow | **menu** (`2`/`4`/`9`/`e`/ESC) → `4` = CLI → `bootipq`; `bootdelay=2` | `bootipq` after 5 s countdown |
| u-boot prompt | `IPQ807x#` | `=>` |
| `active_fw` | `0` (slot at `0x1000000`) | `0` |
| Secure boot | not fused — custom FIT boots | not fused |
| Hardware ID | `hw_id=0101012B`, `pro_id=000` | — |
| MAC source | **u-boot env `ethaddr`** and `cert` partition (ART has none) | ART |

MTD map is identical to the documented one (`0:SBL1` … `0:ART@0xf80000`, `rootfs@0x1000000` 111 MiB,
`0:WIFIFW@0x7f00000`, `rootfs_1@0x8800000`, `0:WIFIFW_1@0xf700000`).

### Getting to a u-boot prompt on this bootloader

The "press any key" trick from the older unit does nothing here. After the DDR/NAND init the console prints a menu:

```
Please choose the operation:
   2: Load Linux System code then write to Flash via TFTP.
   4: Entr boot command line interface.
   9: Load Boot Loader code then write to Flash via TFTP.
   e: Erase Boot Loader ENV config.
   ESC: Please input ESC to run Burn-in testing.
```

Press **`4`** (a few times, from the moment `U-Boot 2016.01` appears) to reach `IPQ807x#`. **Do not press `e` or `9`.**
The stock console is password-protected and the documented default (`admin`) is rejected on this unit, so power-cycling
into u-boot is the way in; it also stops the stock OS (and its Wi-Fi) from starting.

## What was tested

| Area | Result | Evidence |
|---|---|---|
| Full NAND backup (boot region, ART, both rootfs slots, both wififw) over TFTP | ✅ | all six files re-hashed after copy |
| RAM boot of initramfs | ✅ | `Machine model: EnGenius EWS377-FIT`, 512 MiB, ath11k + NSS up |
| Flash `factory.ubi` to slot 0, read back | ✅ | `cmp.b` of 15,204,352 bytes identical |
| Persistent boot from NAND | ✅ | `bootipq` → `config@hk07` → UBI `ubi0` → squashfs + `rootfs_data` UBIFS overlay |
| Config persists across reboot | ✅ | root password, static IP, SSIDs all survived |
| LAN MAC | ✅ | `lan`/`br-lan` = the unit's real MAC (from u-boot env) |
| Wi-Fi MACs | ✅ after fix | stable, derived from LAN MAC (+1, +2); random before the fix |
| Ethernet | ✅ | 1 Gb/s link, 939 Mbit/s to the AP / 856 Mbit/s from the AP (iperf3) |
| Wi-Fi 5 GHz (ch36, HE80, WPA2) | ✅ | 802.11ax MCS11 ×2 stream; ~390 Mbit/s up / ~440 Mbit/s down at −67 dBm; BSSID matches derived MAC |
| Wi-Fi 2.4 GHz (ch1, HE20, WPA2) | ⚠️ works, slow | associates and passes traffic; only 27 / 73 Mbit/s at a strong −39 dBm with many retransmits — see [Open items](#open-items) |
| DHCP/bridging for Wi-Fi clients | ✅ | client got a lease; isolated from LAN (separate bridge + firewall zone) |
| `sysupgrade -T` then `sysupgrade -n` | ✅ twice | upgrade, reboot, correct model/MAC afterwards |
| Health | ✅ | no kernel errors besides the known ones below, ~45 °C idle, RAM 370 MB usable |

## Findings

1. **Wi-Fi board data was wrong in multi-device builds (build-config bug, fixed).** The October multi-profile build
   selected all three `ipq-wifi-engenius_*` packages and used one shared rootfs; every image shipped the *EWS377AP v3*
   `board-2.bin`. On the FIT, ath11k asks for `variant=EnGenius-EWS377-FIT`, finds nothing, and the radios never start
   (`failed to fetch board data … qmi failed to fetch board file: -12`). Fix: build each SKU as its own single-profile
   build so only its own board file is installed (`ews377ap-v3-port/build-skus.sh`).
   Verified by unpacking each image's rootfs and hashing `board-2.bin`.
2. **MAC address.** ART on this unit starts with `0xff` and the calibration block holds Atheros placeholder MACs
   (`00:03:7f:12:34:56…`); u-boot's SROM MAC is the placeholder `00:03:7f:ba:db:ad`. The real MAC is `ethaddr` in the
   u-boot env (`0:APPSBLENV`) and in the `cert` partition's `SN/MAC/HWID` record. The `nvmem-layout "u-boot,env"`
   binding already in `ipq8072-engenius-ap-hk07.dtsi` reads it correctly for the LAN port (env size `0x40000` matches).
   Wi-Fi radios still got random MACs, so `11_fix_wifi_mac` now derives them from the LAN MAC.
3. **The guide's single-shot backup command crashes this u-boot.** `nand read 0x44000000 0x1000000 0x6f00000` (111 MiB)
   overwrites u-boot's own control FDT (`fdtcontroladdr=4a970ec0` on this 512 MiB unit); the AP resets and boots stock.
   Read big slots in ≤ 32 MiB chunks and join them on the server (all below `0x4a000000`).
4. **No `fw_printenv`/`fw_setenv`** on the OpenWrt image (`/etc/fw_env.config` is not provided), so the WAX218-style
   env-based first-boot provisioning does not work on these boards yet.

Known/benign: two `clk_disable_unused` call traces at ~2.4 s during boot; `psci: [Firmware Bug]: failed to set PC mode`;
`Block protection check failed` from the NAND driver. None affected operation.

## Not yet tested

- 2.5 GbE link negotiation (only a 1 G switch was available)
- Reset button / failsafe mode, LED behaviour beyond the blue status LED being on
- Power-cycle (cold boot) persistence after the final flash — reboot and `sysupgrade` reboots were tested
- Invalid-image rejection, downgrade/rollback behaviour, calibration persistence across sysupgrade (the second
  sysupgrade used `-n`; calibration is read from ART at every boot)
- Wi-Fi under load for long periods, WPA3, DFS channels, regulatory domain
- ECW230v3: the same code paths build and the board file differs, but no ECW230v3 unit has been tested

## Open items

- 2.4 GHz throughput is low in this (noisy) environment; try other channels / a second client before calling it a bug.
- Provide `fw_env.config` for `0:appsblenv` (env size `0x40000`) so `fw_printenv`/`fw_setenv` work.
- Upstream the MAC handling: parse the `cert` `SN/MAC/HWID` record or keep using u-boot env; document that ART MACs
  are placeholders on the FIT.

## Install procedure that was tested (this unit)

1. UART 115200 8N1; power-cycle and press `4` at the menu → `IPQ807x#`.
2. `setenv ipaddr <free ip>; setenv serverip <tftp host>; ping $serverip`.
3. **Back up first** (chunked, see finding 3): `nand read 0x44000000 <off> <≤0x2000000>` + `tftpput`, for
   `0x0–0x1000000`, ART, both rootfs slots and both wififw partitions. Keep them off the device and out of git — the
   boot region contains the unit's cloud private key.
4. `tftpboot 0x44000000 openwrt-…-ews377-fit-squashfs-factory.ubi` → expect `Bytes transferred = 15204352 (e80000 hex)`.
5. `nand device 0; nand erase 0x1000000 0x6f00000; nand write 0x44000000 0x1000000 0xe80000`, then
   `nand read 0x48000000 0x1000000 0xe80000; cmp.b 0x44000000 0x48000000 0xe80000`.
6. `active_fw` was already `0`, so no `saveenv` was needed (this leaves the env, and the MAC, untouched). `reset`.
7. First boot: set a root password immediately; LAN defaults to DHCP client.
