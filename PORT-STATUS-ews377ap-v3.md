# Port status — EnGenius EWS377AP v3 (`ap-hk07`, IPQ8072A)

Target **C** (NSS-EDMA) port, on branch `ews377ap-v3`, forked from
`JuliusBairaktaris/openwrt-nss-edma` (NSS offload on the **upstream** qca_edma/qca_ppe stack).

This is a **scaffold**, not a working build. It establishes the file skeleton from the closest
in-tree template so the remaining work is "fill in verified hardware values," not "start from zero."

## Why this template

`ipq8072-eap660hd-v1.dts` (TP-Link EAP660 HD v1) is the closest in-tree device: same IPQ8072,
dual-band 4×4, single 2.5 GbE uplink (QCA8081 @ 2500base-x), NAND with `qcom,smem-part`. The
EWS377AP v3 board `ap-hk07` is a Qualcomm HK reference derivative, as is EAP660HD — so most of the
DTS should transfer. Every transferred value is marked `TODO(extract)` until confirmed on hardware.

## Files added

| File | State |
|---|---|
| `target/linux/qualcommax/dts/ipq8072-engenius-ews377ap-v3.dts` | scaffold from EAP660HD; placeholders flagged |
| `target/linux/qualcommax/image/ipq807x.mk` — `Device/engenius_ews377ap-v3` | FitImage + UbiFit sysupgrade; factory (senao-header) stubbed |
| `package/firmware/ipq-wifi/Makefile` — `ipq-wifi-engenius_ews377ap-v3` | package registered; **board-2.bin not yet supplied** |

## CONFIRMED from OEM firmware (offline extraction, 2026-09-02)

Pulled `fdt@hk07` (the **default configuration**) out of the stock EWS377-FIT 1.1.30 kernel FIT and
decompiled it — model *"Qualcomm IPQ807x/AP-HK07"*, i.e. exactly this board. Values now in the DTS:

- **LEDs:** single RGB status LED, active-high — GPIO **54** (R) / **55** (G) / **56** (B).
- **Reset button:** GPIO **52**, active-low, `KEY_RESTART`.
- **MDIO/PHY:** internal gigabit PHYs at addr 0–4; **2.5G uplink PHY (QCA8081) at addr 28** (ESS
  port 6 / WAN in the reference). PHY reset via GPIO **43** (active-high) + GPIO **44** (active-low).
- **Partitions:** OEM defines them in SMEM (QSDK), so `qcom,smem-part` auto-reads the layout.
- **WiFi firmware:** QSDK `WLAN.HK.2.5.r4-00745` (QCA8074_v2). Board-data set extracted: default
  `bdwlan.bin == bdwlan.b210`; the note confirms **ECW230v3 uses `bdwlan.b290`**.

Extraction artifacts (decompiled OEM DTS + board-data blobs + notes) are staged in the
`ews377apv3-openwrt` planning repo under `reference/`.

## Still blocking — need the running unit / UART (ETA ~2 days)

1. **Secure-boot fuse state** — go/no-go for booting any custom image at all.
2. **WiFi qmi-board-id** — mainline ath11k requests board data by the board-id it reads from the
   chip at probe. Read it from the first ath11k boot log, then pack the matching `bdwlan` blob into a
   `board-2.bin` (via `ath11k-bdencoder`) as `package/firmware/ipq-wifi/board-engenius_ews377ap-v3.*`
   and set the DTS `qcom,ath11k-calibration-variant` to match.
3. **Ethernet port population** — confirm whether any gigabit port (phy 0–4) is physically exposed on
   the EWS377 enclosure, or only the 2.5G PoE uplink.
4. **Install format** — verify the exact `mksenaofw` flag mapping (vendor 0x0101 / product 0x011a)
   against a de-obfuscated OEM `.bin` before shipping the factory image.
5. **PHY reset** — confirm a single reset on GPIO43 brings all PHYs up (QSDK toggles 43+44).

## Suggested next steps (in order)

1. Extract OEM DTS + `/lib/firmware/IPQ8074` from a de-obfuscated stock image (offline, no hardware) —
   fill in items 2–4 above from real data.
2. Hook up UART (header J2, 3.3V, 115200 8N1); run the secure-boot check (item 1); TFTP an initramfs
   build of this branch to prove console + Ethernet non-destructively.
3. Iterate DTS until console/Ethernet/WiFi come up; then test sysupgrade to a non-OEM slot.
4. Only then layer/verify the NSS-EDMA offload gates (see Phase 7 in the planning repo).

## Recovery

Dual A/B OEM slots + UART + TFTP. Keep one OEM slot intact. Back up mtd11 (ART) before any flash —
its corruption is a real brick.
