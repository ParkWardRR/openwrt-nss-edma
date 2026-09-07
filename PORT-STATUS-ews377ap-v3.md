# Port status — EnGenius EWS377AP v3 (`ap-hk07`, IPQ8072A)

Target **C** (NSS-EDMA) port, on branch `ews377ap-v3`, forked from
`JuliusBairaktaris/openwrt-nss-edma` (NSS offload on the **upstream** qca_edma/qca_ppe stack).

**🎉 VALIDATED ON HARDWARE (2026-09-06):** OpenWrt is **installed and running persistently from NAND**
on a real EWS377AP v3 (ScuderiaToroRosso). Full end-to-end: `bootipq` → FIT `config@hk07` → kernel →
UBI root mount (`ubi0` on the `rootfs` partition, 887/1 PEBs, factory bad block skipped) → squashfs
root + `rootfs_data` UBIFS overlay → `root@OpenWrt:~#`. Ethernet up, both WiFi radios functional
(tested WPA2, torn down), config **persists across real reboots**. Secure boot confirmed not fused.

Build: kernel 6.18.44; artifacts `initramfs-uImage.itb`, `squashfs-sysupgrade.bin`, bare
`squashfs-factory.ubi`, `squashfs-qsdk-factory.itb` (OEM-updater FIT), with `ath11k-firmware-ipq8074`
+ `ipq-wifi-engenius_ews377ap-v3` (board_id 0x290).

### The two fixes that unlocked NAND boot (both on hardware)
1. **FIT config name** — OEM `bootipq` selects the FIT config by board name `config@hk07` and aborts
   ("Config not availabale") on the default `config@1`. Set `DEVICE_DTS_CONFIG := config@hk07` (like
   the sibling ap-hk07 board `netgear_wax218`). *This was the boot-loader blocker.*
2. **Install to slot 0** — OpenWrt's qualcommax root-mount always targets the SMEM/DTS partition
   labeled `rootfs` = mtd12 @0x1000000 (slot 0), regardless of which slot u-boot loaded the kernel
   from. So OpenWrt must be written to **slot 0** (also the only slot the OEM installer writes).
   Single-slot; the OEM A/B fallback is not used.

Install method (u-boot): `nand erase 0x1000000 0x6f00000` then `nand write <addr> 0x1000000 <ubisize>`
of the bare `factory.ubi`, `active_fw=0`, `reset`. `nand write` skips the BBT-registered factory bad
block (0x3980000) and UBI is bad-block-tolerant, so slot 0 writes cleanly.

Design notes + extracted reference data are in [`ews377ap-v3-port/`](ews377ap-v3-port/README.md).

## Template

Initially derived from `ipq8072-eap660hd-v1.dts`, then re-based on **`ipq8071-ap8220.dts`** — the
closest in-tree analog for this board's Ethernet wiring (2.5G QCA8081 on `port@6` via `uniphy2`).
Values are confirmed against the decompiled OEM `fdt@hk07`; only the few items that need the running
unit remain `TODO`.

## Files added

| File | State |
|---|---|
| `target/linux/qualcommax/dts/ipq8072-ews377ap-v3.dts` | scaffold from EAP660HD; placeholders flagged |
| `target/linux/qualcommax/image/ipq807x.mk` — `Device/engenius_ews377ap-v3` | FitImage + UbiFit sysupgrade; factory (senao-header) stubbed |
| `package/firmware/ipq-wifi/Makefile` — `ipq-wifi-engenius_ews377ap-v3` | package registered; **board-2.bin not yet supplied** |

## CONFIRMED from OEM firmware (offline extraction, 2026-09-02)

Pulled `fdt@hk07` (the **default configuration**) out of the stock EWS377-FIT 1.1.30 kernel FIT and
decompiled it — model *"Qualcomm IPQ807x/AP-HK07"*, i.e. exactly this board. Values now in the DTS:

- **LEDs:** single RGB status LED, active-high — GPIO **54** (R) / **55** (G) / **56** (B).
- **Reset button:** GPIO **52**, active-low, `KEY_RESTART`.
- **MDIO/PHY:** internal gigabit PHYs at addr 0–4; **2.5G uplink PHY (QCA8081) at addr 28**. PHY
  reset via GPIO **43** (active-high) + GPIO **44** (active-low). MDIO pins: mdc=gpio68, mdio=gpio69.
- **Ethernet topology (fully translated to mainline bindings):** uniphy0 = QCA8075 5×GbE on ports
  1–5 (PSGMII, `switch_mac_mode=0x00`); uniphy2 = the 2.5G QCA8081 on **ESS port 6** (USXGMII,
  `switch_mac_mode2=0x0f`); uniphy1 unused. `switch_cpu_bmp=0x01`, `lan_bmp=0x3e`, `wan_bmp=0x40`.
  The DTS wires the confirmed uplink as `port@6` → `qca8081_28` (`ethernet-phy-id004d.d101`),
  `phy-mode="2500base-x"`, `pcs-handle=<&uniphy2 0>` — matching the in-tree `ipq8071-ap8220` 2.5G AP.
  The 5× gigabit block is documented but omitted (AP almost certainly doesn't expose it).
- **Partitions:** OEM defines them in SMEM (QSDK), so `qcom,smem-part` auto-reads the layout.
- **WiFi firmware:** QSDK `WLAN.HK.2.5.r4-00745` (QCA8074_v2). **Board id = `0x290`** in both OEM
  DTBs → board-data blob **`bdwlan.b290`** (same as ECW230v3).
- **LEDs (refined):** user-facing RGB status LED is a direct `gpio-leds` on GPIO54/55/56 (both DTBs)
  — driven here. The functional pwr/lan/2.4G/5G/scan/ble indicators use the Qualcomm `qca,ledc`
  hardware controller (gpio18/19/20 serial), which mainline has **no driver** for — not wired.
- **Ethernet (refined):** the shipping firmware's `/etc/config/network` has a single `lan = eth0`,
  confirming the AP exposes only the one 2.5G uplink. RAM = 512 MB (`MP_512`).

Extraction artifacts (decompiled OEM DTS + board-data blobs + notes) are staged in the
`ews377ap-v3-port/reference/`.

## Resolved on hardware (2026-09-06)

1. **Secure-boot fuse state** — ✅ not fused (direct fuse read); custom images boot.
2. **WiFi board data** — ✅ both radios come up. Bench proved the stock/generic board-2.bin already
   satisfies `qmi-board-id=255`; caldata handoff from ART works via the `11-ath11k-caldata` hotplug.
3. **Ethernet** — ✅ single 2.5G `lan` uplink (QCA8081@28, `2500base-x`/uniphy2) is the exposed port;
   `eth0` is the internal CPU conduit. `ethtool lan` advertises 10/100/1000/2500; observed speed is
   link-partner-limited (1G bench switch), not a defect. No gigabit ports exposed on the enclosure.
4. **Install format** — ✅ two paths: (a) u-boot TFTP + `nand write` of the bare `factory.ubi` to
   slot 0 (the validated method); (b) `qsdk-factory.itb` FIT for the OEM updater pipeline (built,
   not yet exercised). Senao-header web-UI factory image still stubbed (optional).
5. **NAND boot** — ✅ `config@hk07` + slot-0 install (see banner) — persistent, reboot-surviving.

## Remaining / minor
- 2.5G speed needs a 2.5G-capable switch partner to observe 2500 (test-bench topology, not a fix).
- NSS-EDMA offload: built in; confirm throughput gains under load (see `ews377ap-v3-port/porting-plan.md` Phase 7).
- Upstreaming to mainline OpenWrt (strip NSS + fork-only bits): see `ews377ap-v3-port/UPSTREAMING-PLAN.md`.
- Slot 1 (mtd14) holds a harmless partial image from an aborted A/B attempt; can be re-erased later.

## Recovery

Single-slot now (OpenWrt on slot 0). Rollback: TFTP the byte-exact OEM `oem-rootfs.bin` dump back to
slot 0 via the same `nand erase 0x1000000 0x6f00000` / `nand write` sequence (u-boot skips the factory
bad block). Full backups (mtd12/mtd14/mtd7/mtd8/mtd11) are held off-device. Never write mtd11 (ART) —
its corruption is the only true brick; secure boot is unfused so u-boot + TFTP always recover.
