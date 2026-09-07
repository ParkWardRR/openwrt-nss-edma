# Upstreaming the EWS377AP v3 to OpenWrt — plan for review

Goal: get EnGenius **EWS377AP v3** (IPQ8072A, `ap-hk07`) into **mainline OpenWrt**
(`openwrt/openwrt`, target `qualcommax/ipq807x`). This is a review draft — nothing is submitted yet.

> **STATUS (2026-09-06):** the fork port is **COMPLETE and hardware-validated** (community build v0.1
> released). Mainline upstreaming per this plan is still **TODO / not submitted**. Note for the PR:
> the hardware-proven install needs the FIT config named `config@hk07` (`DEVICE_DTS_CONFIG :=
> config@hk07`) and OpenWrt installed to the `rootfs` slot 0 — carry both into the mainline recipe.

## 0. The key distinction: mainline ≠ our NSS-EDMA fork

All our work so far is on the **`JuliusBairaktaris/openwrt-nss-edma` fork**, which adds Qualcomm NSS
offload on top of OpenWrt. **Mainline OpenWrt has none of the NSS packages/patches.** So:

- **Upstreaming = board support only** — the DTS, image recipe, board.d entries, caldata hotplug, and
  (maybe) a board-2.bin. **The NSS offload does NOT go upstream** (it's the fork's domain).
- The board must be **re-tested on a clean mainline build** before submitting — several of our fixes
  were fork-specific (see §2). Mainline ath11k on IPQ8074 already works for many devices (AP8220,
  DL-WRX36, AX3600), so the board should come up on mainline with the standard pieces.

## 1. Files to submit (mainline paths)

| File | Change |
|---|---|
| `target/linux/qualcommax/dts/ipq8072-ews377ap-v3.dts` | New DTS (cleaned — see §2) |
| `target/linux/qualcommax/image/ipq807x.mk` | New `Device/engenius_ews377ap-v3` (FitImage + UbiFit; Senao factory image) |
| `target/linux/qualcommax/ipq807x/base-files/etc/board.d/02_network` | Add board (single `lan`, dhcp) + **MAC from ART** (see §3) |
| `target/linux/qualcommax/ipq807x/base-files/etc/hotplug.d/firmware/11-ath11k-caldata` | Add board → `caldata_extract "0:art" 0x1000 0x20000` |
| `01_leds` (optional) | Default LED triggers for the RGB status LED |
| board-2.bin | **Separate PR** to the `firmware/qca-wireless` feed — only if the stock ath11k-firmware doesn't already cover us (see §2) |

## 2. Fork-specific things to re-check/strip before upstream ⚠️

These made it work on the fork but may be **wrong or unnecessary for mainline** — verify each on a
clean mainline build:

1. **`qcom,ath11k-fw-memory-mode = <1>`** (in `&wifi`). This is read by the fork's ath11k **patch 903**.
   Mainline ath11k may not support this DT property at all → the line could be a no-op or a dtc
   warning. **Action:** check whether mainline AX3600 DTS sets it; if mainline has no such binding,
   drop the line and rely on mainline's default mem mode.
2. **`kmod-ath11k-ahb` AUTOLOAD.** We added `AUTOLOAD` because the fork's package lacked it. **Mainline
   almost certainly already has it** (that's why AP8220 etc. work) → our change is fork-only, not part
   of the upstream diff.
3. **Custom `board-2.bin` (`ipq-wifi-engenius_ews377ap-v3`).** On the fork we packed `bdwlan.b290`
   keyed `qmi-board-id=255,variant=EnGenius-EWS377AP-v3`. But the bench proved the **stock generic
   board-2.bin already satisfies `qmi-board-id=255`**, and WiFi came up with it. **Action:** test
   mainline with NO custom board-2.bin first (just `qcom,ath11k-calibration-variant` + caldata). If
   radios calibrate fine, **omit the custom board-2.bin** — cleaner upstream. Only submit a
   qca-wireless board file if a device-specific variant is genuinely needed.
4. **`ipq-wifi` `Build/Prepare`** (files/ merge) — a fork-repo fix; not relevant if we don't ship a
   custom board file upstream.
5. **Firmware path (`/lib/firmware/IPQ8074/` vs `ath11k/IPQ8074/hw2.0/`)** — the mismatch we hit was
   fork packaging; mainline installs to the correct ath11k path. Non-issue upstream.

Net: the upstream DTS is likely **simpler** than our fork DTS (drop fw-memory-mode if unsupported; no
board-2.bin override needed). The genuinely portable, board-specific content is: compatible/model,
LEDs (GPIO 54/55/56), reset (GPIO 52), MDIO+PHY (QCA8081@28), the `port@6`/uniphy2 2.5G uplink,
`qcom,smem-part`, and `qcom,ath11k-calibration-variant`.

## 3. Must-add before upstream: proper MAC from ART

Our `02_network` entry sets up the `lan` interface but **no MAC assignment** — upstream devices read
the real MAC from ART. Add an `ipq807x_setup_macs` case, e.g. (offset TBD — verify against ART dump):
```
engenius,ews377ap-v3)
    lan_mac=$(mtd_get_mac_binary "0:ART" <offset>)   # confirm offset from mtd11-art.bin
    label_mac=$lan_mac
    ;;
```
Also confirm ath11k picks the per-radio MACs from ART/board (base MAC +1/+2 as the OEM does).

## 4. DTS cleanliness for upstream

- Drop the verbose "CONFIRMED (OEM …)" comments or trim to concise ones (upstream style).
- Keep SPDX header, `model = "EnGenius EWS377AP v3"`, `compatible = "engenius,ews377ap-v3","qcom,ipq8074"`.
- Document (commit body, not DTS) that the OEM functional LEDs use `qca,ledc` (no mainline driver) so
  only the RGB gpio-leds are wired — reviewers will ask.
- Verify it builds with **no dtc warnings** on mainline.

## 5. Testing evidence to include in the PR

From a **mainline** build (RAM boot + a flashed unit):
- Boots to shell; `/proc/mtd` matches `qcom,smem-part`.
- 2.5G `lan` link (`ethtool lan` = 2500 against a 2.5G partner).
- Both WiFi radios: `iw dev` after `wifi up`, AP mode, sane txpower, client assoc + throughput.
- **sysupgrade** (persist across upgrade) and **failsafe** (reset-held) both work — reviewers require this.
- LEDs (54/55/56) + reset button (GPIO 52) events.
- The exact install path (Senao factory image via OEM updater, or u-boot) documented + a rollback path.

## 6. Submission mechanics

1. Fork `openwrt/openwrt`; branch `ews377ap-v3`.
2. Rebase our board files onto mainline; apply the §2 cleanups; build clean.
3. One commit: `qualcommax: add support for EnGenius EWS377AP v3`, standard OpenWrt commit body
   (specs: SoC, RAM, flash, WiFi, ports, LEDs; install method), **`Signed-off-by:`** (DCO required).
4. If a board-2.bin is needed: separate PR to `openwrt/firmware/qca-wireless` first, then bump the
   `ipq-wifi` version + add the package line in the device commit.
5. Open the PR; add a **device wiki/techdata page**; respond to CI + maintainer review (robimarko et al.).
6. Optional: post the bring-up story (secure-boot open, board-2.bin/caldata, the 2.5G port) in the PR
   for reviewer context.

## 7. Pre-submission checklist

- [ ] Clean **mainline** build boots on hardware (not just the fork).
- [ ] fw-memory-mode line: kept only if mainline supports the binding; else dropped.
- [ ] Custom board-2.bin: dropped if stock firmware suffices (preferred), else qca-wireless PR ready.
- [ ] ART MAC assignment added + verified.
- [ ] sysupgrade + failsafe tested.
- [ ] 2.5G confirmed on a 2.5G partner.
- [ ] dtc builds warning-free; commit has DCO sign-off.
- [ ] Device wiki page drafted.

---
**Bottom line:** the hard bring-up work is done and proven on the fork. Upstreaming is mostly
*subtraction* (strip NSS + fork-only fixes) + a clean mainline retest + the standard PR hygiene
(MAC-from-ART, sysupgrade/failsafe evidence, DCO). Estimate: a focused day once a mainline build is
retested on hardware.
