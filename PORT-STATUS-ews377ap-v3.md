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

## Blocking unknowns — need hardware extraction (UART / de-obfuscated OEM firmware)

These must be pulled from the OEM device tree + `/lib/firmware/IPQ8074` and substituted before a
build is trustworthy (see the extraction plan in the `ews377apv3-openwrt` planning repo):

1. **Secure-boot fuse state** — go/no-go for booting any custom image at all.
2. **GPIOs** — status/power/per-band LED lines + colors; reset button; PHY reset. (placeholders inherited)
3. **Ethernet uplink** — PHY model + MDIO address + ESS port index + link speed. (EAP660HD values assumed)
4. **WiFi board data** — extract OEM `board-2.bin`/`bdwlan` → repackage with the correct board-ID as
   `package/firmware/ipq-wifi/board-engenius_ews377ap-v3.*`, and make the DTS
   `qcom,ath11k-calibration-variant` string match it.
5. **Install format** — verify the exact `mksenaofw` flag mapping (vendor 0x0101 / product 0x011a)
   against a de-obfuscated OEM `.bin` before shipping the factory image.

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
