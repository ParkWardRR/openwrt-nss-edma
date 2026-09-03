# EnGenius EWS377AP v3 (`ap-hk07`) — NSS-EDMA port

Working notes and extracted reference data for porting the **EnGenius EWS377AP v3** (Qualcomm
IPQ8072A, board `ap-hk07`) to this OpenWrt NSS-EDMA tree. The port itself lives in the normal tree
locations; this directory is the design/reference companion.

> **Status:** pre-flash. Device tree drafted and WiFi board data identified from OEM firmware
> (offline); secure-boot check + first boot pending UART. See `../PORT-STATUS-ews377ap-v3.md`.

## Port files in the tree

- `target/linux/qualcommax/dts/ipq8072-engenius-ews377ap-v3.dts` — device tree
- `target/linux/qualcommax/image/ipq807x.mk` — `Device/engenius_ews377ap-v3`
- `package/firmware/ipq-wifi/Makefile` — `ipq-wifi-engenius_ews377ap-v3`

## This directory

| File | Purpose |
|---|---|
| `porting-plan.md` | End-to-end plan: bring-up → DTS → WiFi → NSS validation → install |
| `uart-extraction-plan.md` | What to pull off the unit once UART is connected |
| `hardware-reference.md` | MTD map, boot chain, u-boot env, recovery |
| `research-notes.md` | Community findings: secure-boot priors, prior art, sizing |
| `reference/` | Decompiled OEM device trees + WiFi board data + `board-2.bin` build recipe |

## Confirmed from OEM firmware (both FIT 1.1.30 and native managed v3.9.3.2)

- SoC IPQ8072A, `ap-hk07`; 512 MB RAM; SMEM-defined partitions (`qcom,smem-part`).
- 2.5G uplink: QCA8081 @ MDIO 28 = ESS `port@6` via `uniphy2` (USXGMII). Single port (`lan=eth0`).
- RGB status LED: `gpio-leds` on GPIO 54/55/56 (active-high). Reset button GPIO 52 (active-low).
- WiFi `qcom,board_id = 0x290` → board data `bdwlan.b290` (shared with ECW230v3).
- Functional pwr/lan/wifi LEDs use the `qca,ledc` controller — **no mainline driver**, not wired.

## Pending (needs the unit / UART)

Secure-boot fuse state (go/no-go), exact ath11k board-id string to finalize `board-2.bin`,
`mksenaofw` factory-image flags, and PHY-reset validation. Do all work on a **sacrificial unit**.
