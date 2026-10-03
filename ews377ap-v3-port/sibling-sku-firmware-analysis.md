# Sibling SKU firmware analysis — ECW230v3 + EWS377-FIT

Date: 2026-10-02
Firmware analyzed:
- `EWS377APv3-v3.9.3.2_c1.9.51.bin` (from `EWS377APv3-v3.9.3(2).zip`)
- `Cloud6_4x4_ECW230v3_firmware_v1.8.114-1(2).bin`
- `ews377-fit-1.0.50-2(2).bin`

## Senao firmware header format

All three use the same XOR-encrypted Senao firmware format:

| Field | Offset | EWS377APv3 | ECW230v3 | EWS377-FIT |
|---|---|---|---|---|
| Product ID | 0x08 | 0x011a (282) | 0x011c (284) | 0x012c (300) |
| Version string | 0x0C | 3.9.3.2 | 1.8.114-1 | 1.0.50-2 |
| Payload size | 0x20 | 28,185,216 | 44,307,728 | 32,773,940 |
| Model string | 0x80 | EWS377APv3 | ECW230v3 | EWS377-FIT |
| Header size | — | 146 bytes | 144 bytes | 146 bytes |
| XOR key | — | `783c9ecf67b359ac` | same | same |
| Magic after decrypt | — | `d00dfeed` (FIT) | same | same |

Decryption: XOR the payload (file minus header) byte-by-byte with the
8-byte repeating key `783c9ecf67b359ac`. All three decrypt to valid FIT
images (flattened device tree, magic `0xd00dfeed`).

## FIT image structure

Each decrypted payload is a QSDK-style "flash FIT" containing a u-boot
script + UBI root image + WiFi firmware UBI:

| Sub-image | EWS377APv3 | ECW230v3 | EWS377-FIT |
|---|---|---|---|
| script (flash.scr) | 1,997 B | 3,627 B | 3,003 B |
| UBI root | 25,559,040 B | 41,549,824 B | 27,787,264 B |
| WiFi FW v2 (UBI) | 2,621,440 B | 2,752,512 B | 2,621,440 B |
| WiFi FW v1 (UBI) | — | — | 2,359,296 B |

The UBI root image name hash differs between EWS377 variants
(`dcf446f473bd...`) and ECW230v3 (`841371bb56a8...`).

## NAND partition layout (from flash scripts)

All three write to the same NAND offsets:

| Partition | Offset | Size | Content |
|---|---|---|---|
| rootfs (slot 0) | 0x01000000 | 0x06f00000 (112 MB) | UBI root image |
| wififw | 0x07f00000 | 0x00900000 (9 MB) | WiFi firmware (SquashFS in UBI) |

ECW230v3's flash script additionally validates `soc_hw_version` (must be
`200d0100`/`200d0101`/`200d0102`/`200d0200`) and `machid` before flashing.
EWS377APv3/FIT scripts do not perform these checks.

## Kernel FIT images (inside UBI root)

Each UBI root contains a kernel FIT with multiple board DTBs:

| Property | EWS377APv3 | ECW230v3 | EWS377-FIT |
|---|---|---|---|
| Kernel version | 4.4.60 | 5.4.213 | 4.4.60 |
| **Default config** | `config@hk07` | `config@hk08` | `config@hk07` |
| Has `fdt@hk07` | yes | yes | yes |
| Total FDT count | 21 | 25 | 21 |

**ECW230v3 defaults to `config@hk08`**, not `config@hk07`. This is the
only device that differs. It does include an `fdt@hk07` DTB as well.
This needs hardware verification to determine which config the ECW230v3
u-boot actually selects at boot.

## Device tree comparison (fdt@hk07)

### Compatible strings

| Firmware | compatible | model |
|---|---|---|
| EWS377APv3 | `qcom,ipq807x-hk07`, `qcom,ipq807x` | IPQ807x/AP-HK07 |
| ECW230v3 | `qcom,ipq8074-ap-hk07`, `qcom,ipq8074` | IPQ8074/AP-HK07 |
| EWS377-FIT | `qcom,ipq807x-hk07`, `qcom,ipq807x` | IPQ807x/AP-HK07 |

ECW230v3 uses the newer compatible string format (`ipq8074` vs `ipq807x`),
reflecting its newer QSDK base (kernel 5.4 vs 4.4).

### Hardware — identical across all three

| Component | Value | Verified in all 3 DTBs |
|---|---|---|
| SoC | IPQ8072A | yes |
| LED R | GPIO54, active-high | yes |
| LED G | GPIO55, active-high | yes |
| LED B | GPIO56, active-high | yes |
| HW LED controller | GPIO18/19/20 (qca,ledc) | yes |
| Reset button | GPIO52, active-low | yes |
| MDIO pins | GPIO68 (MDC), GPIO69 (MDIO) | yes |
| Ethernet PHY | QCA8081 @ MDIO addr 28, port 6 | yes |
| PHY reset | GPIO43 active-high, GPIO44 active-low | yes |
| NAND | 128k block, 2048 page, 4-bit ECC | yes |

### Differences between EWS377APv3 and EWS377-FIT DTBs

Only 16 non-trivial differences, all firmware configuration:
- `MP_512` flag present in FIT (reduced memory mode)
- WiFi `tgt-mem-mode = <1>` in FIT vs `<0>` in APv3
- LED default trigger: `timer` (FIT) vs `pwr_led` (APv3)
- Smaller trust zone / WiFi memory reservations in FIT
- No `qseecom` node in FIT
- No `rmnet_rx-enabled` in FIT

**Hardware is identical.** Same DTS can serve both.

### Differences between EWS377APv3 and ECW230v3 DTBs

The ECW230v3 fdt@hk07 uses a newer QSDK DTS structure (kernel 5.4
bindings vs 4.4), so the node layout differs significantly in naming
and organization. However, the **hardware-specific properties are
identical**: same GPIOs, same PHY, same port layout, same flash config.

## WiFi board data (bdwlan.b290) comparison

All three contain `bdwlan.b290` files (board_id 0x290 = 656) extracted
from WiFi firmware SquashFS within the WiFi FW UBI partition.

| Source | SHA256 | Size |
|---|---|---|
| EWS377APv3 | `2877f953dcc74bc1c1068c7a0a4f66d24c84d5b7a59479aeb71c17243352069e` | 131,072 |
| ECW230v3 | `61f98b41e53e9cc9c72846c70350533f20514a3016fe75c68b3a0a83cec0b385` | 131,072 |
| EWS377-FIT | `8be0af19e24558d31cc6fb27dc950e55cdf25c1807b4f54d2b71f96d43fd62c1` | 131,072 |
| Repo (wrapped) | `57c37327c85b0d6f53edb5eaf469723626dd78988b3736e49750ca1e7142d991` | 131,184 |

Byte-level comparison:
- **EWS377APv3 vs EWS377-FIT: 56 bytes differ** (0.04%) — likely
  unit-specific checksums/version fields at offsets 0x0A-0x0B and 0x38
- **ECW230v3 vs EWS377APv3: 6,495 bytes differ** (4.95%) — materially
  different calibration data
- **ECW230v3 vs EWS377-FIT: 6,490 bytes differ** (4.95%)

### Conclusions on board data

1. **EWS377-FIT can likely reuse the EWS377AP v3 board data** — only 56
   bytes differ, all in header/checksum fields, not calibration regions.
   Needs radio test confirmation.
2. **ECW230v3 requires its own board data file** — ~5% of the file
   differs, indicating different RF calibration (possibly different
   antenna tuning, FEM configuration, or regulatory table).
3. **The repo's board data file** (`board-engenius_ews377ap-v3.ipq8074`)
   is a `board-2.bin` container (112-byte header + 131,072 raw data).
   The wrapped data doesn't byte-match any of the three firmware
   extractions, suggesting it came from a different firmware version or
   unit-specific ART partition dump.

### Board data file format

The repo's board-2.bin container uses this header:
```
QCA-ATH11K-BOARD
bus=ahb,qmi-chip-id=0,qmi-board-id=255,variant=EnGenius-EWS377AP-v3
[131,072 bytes of raw board data]
```

For ECW230v3, a new file would need `variant=EnGenius-ECW230v3` (or
similar) and distinct raw board data extracted from the ECW230v3 firmware.

## ECW230v3 system identity (from rootfs)

| Field | Value |
|---|---|
| `/etc/modelname` | `ecw230v3` |
| `/etc/config/system` hostname | `ECW230` |
| `board.cfg` CPU | `IPQ8072` |
| `board.cfg` RF | `QCN5024_QCN5054` |
| `board.cfg` ETH | `QCA8081` |
| OpenWrt base | 19.07-SNAPSHOT (QSDK fork) |
| NSS firmware | `qca-nss0-retail.bin` + `qca-nss1-retail.bin` present |
| LED names (uci) | pwr_led, lan_led, wlan_2g_led, wlan_5g_led |

The LED sysfs names (`pwr_led`, `lan_led`, `wlan_2g_led`, `wlan_5g_led`)
map to the `qca,ledc` hardware LED controller (GPIO18/19/20), not the
direct GPIO LEDs. OpenWrt mainline has no `qca,ledc` driver, so the
direct GPIO RGB LED approach used in the EWS377 DTS is correct.

## What's needed to add ECW230v3 and EWS377-FIT board support

### Approach: shared .dtsi + thin per-device .dts files

Per the upstream playbook (step 7), use a common dtsi:

```
target/linux/qualcommax/dts/
├── ipq8072-engenius-ap-hk07.dtsi      # shared hardware: SoC, RAM, NAND, eth, wifi, GPIOs
├── ipq8072-engenius-ews377ap-v3.dts   # EWS377AP v3 identity + overrides
├── ipq8072-engenius-ecw230v3.dts      # ECW230v3 identity + overrides
└── ipq8072-engenius-ews377-fit.dts    # EWS377-FIT identity + overrides
```

### Per-file changes needed

#### 1. Device tree files

**New `ipq8072-engenius-ap-hk07.dtsi`** — factor out the shared hardware
from the current `ipq8072-ews377ap-v3.dts`:
- SoC includes (ipq8074.dtsi, ipq8074-nss.dtsi, etc.)
- UART, chosen, aliases
- GPIO keys (reset @ GPIO52)
- GPIO LEDs (RGB on GPIO54/55/56)
- MDIO bus (GPIO68/69)
- QCA8081 PHY @ addr 28
- ESS switch + port@6 ethernet
- NAND flash config
- WiFi nodes with ath11k config

**Thin `.dts` files** — each includes the dtsi and sets:
- `compatible = "engenius,ews377ap-v3", "qcom,ipq8074"` (etc.)
- `model = "EnGenius EWS377AP v3"` (etc.)
- `qcom,ath11k-calibration-variant = "EnGenius-EWS377AP-v3"` (etc.)
- Any device-specific overrides (none expected based on firmware analysis)

#### 2. Image Makefile (`target/linux/qualcommax/image/ipq807x.mk`)

Add two new device blocks:

```makefile
define Device/engenius_ecw230v3
    $(call Device/FitImage)
    $(call Device/UbiFit)
    DEVICE_VENDOR := EnGenius
    DEVICE_MODEL := ECW230
    DEVICE_VARIANT := v3
    BLOCKSIZE := 128k
    PAGESIZE := 2048
    SOC := ipq8072
    DEVICE_DTS_CONFIG := config@hk07
    DEVICE_PACKAGES := ipq-wifi-engenius_ecw230v3
    ARTIFACTS := web-ui-factory.fit
    ARTIFACT/web-ui-factory.fit := append-image initramfs-uImage.itb | \
        ubinize-kernel | qsdk-ipq-factory-nand
endef
TARGET_DEVICES += engenius_ecw230v3

define Device/engenius_ews377-fit
    $(call Device/FitImage)
    $(call Device/UbiFit)
    DEVICE_VENDOR := EnGenius
    DEVICE_MODEL := EWS377-FIT
    BLOCKSIZE := 128k
    PAGESIZE := 2048
    SOC := ipq8072
    DEVICE_DTS_CONFIG := config@hk07
    DEVICE_PACKAGES := ipq-wifi-engenius_ews377-fit
    ARTIFACTS := web-ui-factory.fit
    ARTIFACT/web-ui-factory.fit := append-image initramfs-uImage.itb | \
        ubinize-kernel | qsdk-ipq-factory-nand
endef
TARGET_DEVICES += engenius_ews377-fit
```

**Open question for ECW230v3:** The stock firmware defaults to
`config@hk08`. Need to verify on hardware whether the ECW230v3 u-boot
selects `config@hk07` or `config@hk08`. If hk08, set
`DEVICE_DTS_CONFIG := config@hk08` instead.

#### 3. WiFi board data

**`package/firmware/ipq-wifi/Makefile`** — add two new entries:
```makefile
$(eval $(call generate-ipq-wifi-package,engenius_ecw230v3,EnGenius ECW230v3))
$(eval $(call generate-ipq-wifi-package,engenius_ews377-fit,EnGenius EWS377-FIT))
```

**`package/firmware/ipq-wifi/files/`** — add board data files:
- `board-engenius_ecw230v3.ipq8074` — wrap `bdwlan.b290` from ECW230v3
  firmware with variant `EnGenius-ECW230v3`
- `board-engenius_ews377-fit.ipq8074` — can likely reuse the EWS377AP v3
  data with variant `EnGenius-EWS377-FIT`, or extract from EWS377-FIT
  firmware. Needs radio test to confirm.

#### 4. Base files

**`02_network`** — add new compatible strings to the existing
`ucidef_set_interface_lan "lan" "dhcp"` case:
```sh
engenius,ecw230v3|\
engenius,ews377-fit|\
engenius,ews377ap-v3|\
```

**`11-ath11k-caldata`** — add new compatible strings to the
`caldata_extract "0:art" 0x1000 0x20000` case.

**`platform.sh`** — add all three to the `nand_do_upgrade` case
(EWS377AP v3 is currently **missing** from this file — a bug).

#### 5. Web-upload factory images (`mksenaofw`)

Each SKU needs its own product_id in the Senao header:
- EWS377AP v3: `product_id = 0x011a` (282)
- ECW230v3: `product_id = 0x011c` (284)
- EWS377-FIT: `product_id = 0x012c` (300)

The web-ui-factory.fit artifact pipeline already exists for EWS377AP v3.
The same pipeline works for sibling SKUs — only the product_id in the
Senao wrapper header changes. The `qsdk-ipq-factory-nand` image builder
needs to be parameterized per-device, or separate artifact rules added.

## Existing EWS377AP v3 bugs found during analysis

1. **Missing `platform.sh` entry** — `engenius,ews377ap-v3` is not in
   the `nand_do_upgrade` case. Sysupgrade will fail.
2. **Missing `ubi.block=0,rootfs` in bootargs** — the DTS has
   `root=/dev/ubiblock0_1` but omits the `ubi.block=0,rootfs` that
   creates the UBI block device. WAX218 includes both.
3. **No MAC address nvmem** — the DTS has no `nvmem-cells` for reading
   the MAC address from u-boot env, unlike WAX218. The LAN port may get
   a random MAC across reboots.

## Pre-implementation blockers

Before any code changes for ECW230v3 and EWS377-FIT:

1. **ECW230v3 `config@hk07` vs `config@hk08`** — must determine which
   config the ECW230v3 u-boot selects. Requires UART console access to
   an ECW230v3 unit and a boot log capture.
2. **Board data radio testing** — must verify both radios work correctly
   with the extracted board data on each physical unit.
3. **Board data licensing** — extraction proves hardware works; shipping
   requires redistribution rights verification per the playbook (step 4).
4. **Per-unit evidence** — each SKU needs its own evidence archive per
   the playbook (step 0): boot logs, dtb extraction, gpio verification,
   MAC source identification.
