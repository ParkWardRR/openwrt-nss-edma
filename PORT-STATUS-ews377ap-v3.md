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
`ews377apv3-openwrt` planning repo under `reference/`.

## Still blocking — need the running unit / UART (ETA ~2 days)

1. **Secure-boot fuse state** — go/no-go for booting any custom image at all.
2. **WiFi board data** — RESOLVED to a concrete candidate: both OEM DTBs set
   `qcom,board_id = <0x290>`, and the OEM `senaoBDF.note` maps that to **`bdwlan.b290`** (shared with
   ECW230v3 — same hk07 board). Blob is staged in the planning repo. Remaining: read the exact
   ath11k board-id/variant string from the first boot log (expected 0x290), pack `bdwlan.b290` into a
   `board-2.bin` via `ath11k-bdencoder`, drop it as `package/firmware/ipq-wifi/board-engenius_ews377ap-v3.*`,
   and align the DTS `qcom,ath11k-calibration-variant`.
3. **Ethernet port population** — the 2.5G uplink DTS is done; only need to confirm on hardware
   whether any gigabit port (phy 0–4) is *physically exposed* on the EWS377 enclosure (if so, add the
   documented QCA8075 block — and check the 0–4 vs 16–19 PHY strap).
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
