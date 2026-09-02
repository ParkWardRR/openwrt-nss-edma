# Reference artifacts (extracted from OEM firmware)

Pulled offline from de-obfuscated stock firmware — no per-device secrets here (this is the generic
reference board data + device tree, not per-unit ART calibration). Both firmwares boot the **`hk07`**
config by default (model "Qualcomm IPQ807x/AP-HK07").

| File | What |
|---|---|
| `hk07-oem-fit-1.1.30.dts` | Decompiled OEM `fdt@hk07` from **EWS377-FIT 1.1.30** (2023). |
| `hk07-oem-native-v3.9.3.2.dts` | Decompiled OEM `fdt@hk07` from the **native EWS377APv3 managed** fw (2021) — the image that actually ships on the AP. |
| `wifi-board-data/senaoBDF.note` | Senao BDF changelog — maps board id **0x290 → `bdwlan.b290`** (shared with ECW230v3). |
| `wifi-board-data/fw_version.txt`, `SDK_version.txt` | QSDK WiFi FW `WLAN.HK.2.5.r4-00745` (QCA8074_v2). |
| `wifi-board-data/bdwlan.bin.b210-default` | Default board data in the FIT image (== `bdwlan.b210`). |
| `wifi-board-data/bdwlan.b290-ecw230v3` | **The EWS377AP v3 board data** (board id 0x290). |
| `wifi-board-data/BUILD-board-2.bin.md` | How to turn `bdwlan.b290` into a mainline ath11k `board-2.bin`. |

## What the two DTBs establish (cross-confirmed)

- **WiFi:** `qcom,board_id = <0x290>` in both → board data `bdwlan.b290`.
- **RGB status LED:** direct `gpio-leds` on GPIO 54/55/56 (active-high) in both — the user-facing
  blue/amber/red indicator. (Functional pwr/lan/2.4G/5G/scan/ble LEDs run on the Qualcomm `qca,ledc`
  hardware controller, gpio18/19/20 serial — mainline has no driver, so not portable.)
- **Reset button:** GPIO 52, active-low.
- **Ethernet:** 2.5G QCA8081 at MDIO 28 = ESS port 6 / uniphy2 (USXGMII); QCA8075 5×GbE on ports 1–5
  / uniphy0 (PSGMII) in the reference. Shipping `/etc/config/network` uses a single `lan=eth0`, so the
  AP exposes only the 2.5G uplink. MDIO pins mdc=gpio68/mdio=gpio69; PHY reset gpio43/44.
- **RAM:** 512 MB (`MP_512`).
