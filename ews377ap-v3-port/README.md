# EnGenius EWS377AP v3 (`ap-hk07`) — NSS-EDMA port

Working notes and extracted reference data for porting the **EnGenius EWS377AP v3** (Qualcomm
IPQ8072A, board `ap-hk07`) to this OpenWrt NSS-EDMA tree. The port itself lives in the normal tree
locations; this directory is the design/reference companion.

> **Status: ✅ COMPLETE — validated on real hardware (2026-09-06).** OpenWrt boots and runs
> **persistently from NAND**: `bootipq` → FIT `config@hk07` → kernel → UBI root mount → squashfs +
> `rootfs_data` overlay → shell, surviving real reboots. Ethernet, both WiFi radios (WPA2), and config
> persistence all confirmed. Secure boot confirmed **not fused**. Community build **v0.1** published
> (GitHub release `v0.1.0-ews377ap-v3`). See `../PORT-STATUS-ews377ap-v3.md` for the full picture.

## The two fixes that unlocked NAND boot (both found on hardware)

1. **FIT config name** — OEM `bootipq` selects the FIT config by board name `config@hk07` and aborts
   ("Config not availabale") on the default `config@1`. Fixed with `DEVICE_DTS_CONFIG := config@hk07`
   in the device recipe (same as the sibling ap-hk07 board `netgear_wax218`).
2. **Install to slot 0** — OpenWrt's qualcommax root-mount always targets the SMEM/DTS partition
   labeled `rootfs` (= mtd12 @0x1000000, slot 0), regardless of which slot u-boot loaded the kernel
   from. So OpenWrt must live on **slot 0** (also the only slot the OEM installer writes). Single-slot;
   the OEM A/B fallback is not used.

## Port files in the tree

- `target/linux/qualcommax/dts/ipq8072-ews377ap-v3.dts` — device tree
- `target/linux/qualcommax/image/ipq807x.mk` — `Device/engenius_ews377ap-v3` (`config@hk07`; bare
  `factory.ubi` + separate `qsdk-factory.itb` FIT)
- `target/linux/qualcommax/ipq807x/base-files/etc/board.d/02_network` — single 2.5G `lan`
- `target/linux/qualcommax/ipq807x/base-files/etc/hotplug.d/firmware/11-ath11k-caldata` — caldata from ART
- `package/firmware/ipq-wifi/Makefile` — `ipq-wifi-engenius_ews377ap-v3`
- `package/kernel/mac80211/ath.mk` — `ath11k-ahb` AUTOLOAD

## This directory

| File | Purpose |
|---|---|
| `porting-plan.md` | End-to-end plan: bring-up → DTS → WiFi → NSS → install (with final outcomes) |
| `uart-extraction-plan.md` | What was pulled off the unit over UART (done) |
| `hardware-reference.md` | MTD map, boot chain, u-boot env, recovery |
| `research-notes.md` | Community findings: secure-boot priors, prior art, sizing |
| `UPSTREAMING-PLAN.md` | Plan to submit the board to mainline OpenWrt (strip NSS + fork-only fixes) |
| `reference/` | Decompiled OEM device trees + WiFi board data + `board-2.bin` build recipe |

## Confirmed from OEM firmware + hardware (FIT 1.1.30, native v3.9.3.2, and live)

- SoC IPQ8072A, `ap-hk07`; 512 MB RAM; SMEM-defined partitions (`qcom,smem-part`).
- 2.5G uplink: QCA8081 @ MDIO 28 = ESS `port@6` via `uniphy2` (USXGMII). Single exposed port
  (`lan`); `eth0` is the internal CPU conduit. `ethtool lan` advertises up to 2500 (link-partner-limited).
- RGB status LED: `gpio-leds` on GPIO 54/55/56 (active-high). Reset button GPIO 52 (active-low).
- WiFi: both radios functional; the stock/generic `board-2.bin` already satisfies `qmi-board-id=255`,
  caldata handed off from ART via the `11-ath11k-caldata` hotplug. (Custom `bdwlan.b290`/board_id 0x290
  container is retained but not required — see `UPSTREAMING-PLAN.md`.)
- Functional pwr/lan/wifi LEDs use the `qca,ledc` controller — **no mainline driver**, not wired.

## Resolved on hardware (was "pending / needs the unit")

Secure-boot = not fused (go); WiFi radios up (generic board-2.bin suffices); single 2.5G `lan`
confirmed; NAND install method proven (u-boot `nand write` of `factory.ubi` to slot 0); web/QSDK
factory images built (Senao vendor 0x0101 / product 0x011a / type 0, model `EWS377APv3`) but
**community-untested**. Remaining: 2.5G speed needs a 2.5G switch partner to observe 2500; NSS
throughput under load; mainline upstreaming (`UPSTREAMING-PLAN.md`).
