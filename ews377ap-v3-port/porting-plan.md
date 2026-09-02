# OpenWrt (NSS-EDMA) porting plan — EWS377AP v3 (`ap-hk07`, IPQ8072A)

End-to-end plan to bring **OpenWrt with Qualcomm NSS offload** (the NSS-EDMA fork) to the EnGenius
EWS377AP v3. The board is brought up first, then NSS acceleration is enabled and validated on top of
the same port. Ordered so the **go/no-go decision (secure boot)** and the **non-destructive proof
(TFTP initramfs)** come before anything writes to flash.

Working tree: fork `ParkWardRR/openwrt-nss-edma`, branch `ews377ap-v3`. The OEM stock firmware is kept
only as the throughput **baseline to measure against** — it is not a build target.

Bring-up (Phases 0–6) gets the board booting/calibrating on the NSS-EDMA tree; Phase 7 turns on and
validates the NSS offload that is the whole point of using this tree.

---

## Phase 0 — Go/no-go: is secure boot fused?

This single question decides whether the whole effort is possible.

- If the IPQ807x OEM secure-boot / anti-rollback fuse is **blown**, u-boot only runs
  vendor-signed kernels → you'd need EnGenius's private key → **stop, not feasible**.
- If **not blown**, unsigned OpenWrt boots freely.

**Signal we already have:** stock `bootcmd=bootipq` loads a FIT that is only **MD5/CRC-checked in
userspace** (`check_senao_image_header.sh` gates on `product_id`, not a hardware signature). That
strongly implies **no hardware root-of-trust is enforced** — but confirm at the u-boot prompt:

```
# at u-boot over UART (J2, 115200 8N1):
printenv                      # look for secure_boot / sec_auth flags
# dump the security fuse region (QFPROM) if the u-boot build exposes it, or simply:
tftpboot 0x44000000 openwrt-initramfs.itb
bootm 0x44000000              # if an unsigned FIT boots, secure boot is NOT enforced
```

**Deliverable:** a one-line verdict — fused or not.

---

## Phase 1 — Harvest the hardware description (no flashing)  — ✅ done (from firmware)

Done offline from de-obfuscated stock firmware (both FIT 1.1.30 and native managed v3.9.3.2) — the
decompiled OEM DTS and WiFi board data are in `reference/`. Everything here comes from the **stock
QSDK-OpenWrt firmware**: we translate EnGenius's downstream sources instead of reverse-engineering the
board. (1b, the live-unit pull, is superseded — only per-device ART caldata still needs the unit.)

### 1a. From the firmware image (already have de-obfuscated FITs locally)

```
# de-obfuscate senao → FIT (already done: mksenaofw -d fw.bin -o dec.bin)
dumpimage -l dec.bin                       # lists ubi-root + wififw sub-images
dumpimage -T flat_dt -p 1 -o root.ubi dec.bin
# unpack ubi → ubifs → rootfs, then pull:
#   the DTB (appended to the kernel volume / in /boot)
#   /lib/firmware/IPQ8074/*  (board-2.bin, bdwlan*, regdb)
dtc -I dtb -O dts -o hk07-oem.dts <extracted>.dtb   # decompile to readable source
```

### 1b. From a live unit (when a shelled AP is available — see UART plan)

```
cat /proc/mtd
cp /sys/firmware/fdt /tmp/hk07.dtb
tar czf /tmp/wifi-fw.tgz /lib/firmware/IPQ8074
ls /sys/class/leds /sys/class/gpio
ssdk_sh sw dump          # ethernet/switch topology (or swconfig show)
cat /etc/config/*        # uci: network/wireless/system → PHY addrs, port roles
```

**Deliverable:** `hk07-oem.dts` (decompiled), the OEM `/lib/firmware/IPQ8074` tree, and the uci/switch
dumps checked into this repo under `artifacts/`.

---

## Phase 2 — Non-destructive bring-up

Prove the SoC/DDR/console under OpenWrt **without writing flash**.

1. Build (or grab) an OpenWrt **initramfs** `.itb` for the closest in-tree IPQ8074 4×4 profile.
2. `tftpboot` it into RAM and `bootm`. OEM slots stay untouched → instant recovery by power-cycle.
3. Confirm: serial console, ethernet link, `dmesg` clean, ath11k probes (even if RF not yet tuned).

**Deliverable:** an OpenWrt shell over UART with the OEM firmware still intact on flash.

---

## Phase 3 — Device tree for `ap-hk07`  — ✅ largely drafted (offline)

Done from the decompiled OEM `fdt@hk07` (see `reference/`); DTS lives at
`target/linux/qualcommax/dts/ipq8072-engenius-ews377ap-v3.dts` on the fork branch `ews377ap-v3`,
derived from `ipq8071-ap8220` (the closest in-tree 2.5G IPQ8072 AP).

- ✅ **Partitions:** SMEM-defined → `qcom,smem-part` auto-reads DEVCFG/APPSBLENV/APPSBL/cert/ART/rootfs.
- ✅ **Ethernet:** QSDK `ess-switch` translated to mainline — 2.5G uplink = QCA8081 @ MDIO 28, ESS
  **port@6 via uniphy2** (USXGMII); `ethernet-phy-id004d.d101`. Single `lan` (shipping fw uses one
  `eth0`); the reference QCA8075 5×GbE block is documented but omitted.
- ✅ **LEDs + button:** RGB status LED gpio-leds on GPIO 54/55/56 (active-high); reset GPIO 52
  active-low. NOTE: functional pwr/lan/wifi LEDs use the `qca,ledc` controller with **no mainline
  driver** — not portable.
- **Pre-cal:** ath11k reads per-device caldata from **ART (mtd11)** — verify on hardware.

**Deliverable:** `ipq8072-engenius-ews377ap-v3.dts` — drafted; boots to be proven at Phase 2.

---

## Phase 4 — WiFi  — ✅ board data identified (offline)

Stock uses QSDK `qca-wifi`; mainline uses **ath11k**, which looks up board data by a board-ID string.

- ✅ **Board id known:** both OEM DTBs set `qcom,board_id = <0x290>`; OEM `senaoBDF.note` maps that to
  board-data blob **`bdwlan.b290`** (shared with ECW230v3). Blob + `ath11k-bdencoder` recipe staged in
  `reference/wifi-board-data/`.
- **Remaining (needs first boot):** read the exact ath11k board-id/variant string from the boot log
  (expected 0x290), pack `bdwlan.b290` into `board-2.bin`, drop into `ipq-wifi-engenius_ews377ap-v3`,
  and set the DTS `qcom,ath11k-calibration-variant` to match.
- **Then:** verify per-device caldata handoff from ART; confirm TX power / reg-domain look sane.

**Deliverable:** both radios calibrate and pass traffic at expected power.

---

## Phase 5 — Image packaging + install path

Two viable install routes; pick per how secure boot landed:

- **Senao header route:** OpenWrt `firmware-utils` already ships `mksenaofw`. Build a Senao-wrapped
  sysupgrade image (`product_id` matching the target slot) and flash via the OEM updater / one A/B slot.
  The OEM's userspace `check_senao_image_header.sh` only gates on vendor_id+product_id.
- **u-boot route:** after the initramfs boots, write OpenWrt sysupgrade directly to a slot from u-boot.

**Deliverable:** repeatable flash + a documented rollback to stock.

---

## Phase 6 — Finish + upstream

- Add the board profile; test WiFi / eth / LEDs / buttons / **sysupgrade** / **failsafe** / dual-boot.
- Write the commit + device page; open a PR to OpenWrt (`qualcommax` target).
- Keep the OEM slot recovery path documented for anyone flashing back.

---

## Phase 7 — Enable & validate NSS offload

Bring-up (Phases 0–6) gets the board running on the NSS-EDMA tree, but the NSS acceleration — the
reason for using this tree — must be explicitly turned on and proven on the EWS377. The fork drives
the Qualcomm **NSS** block (NAT, PPPoE, SQM, multicast, bridge, ath11k Wi-Fi offload) on an
upstream-oriented **EDMA/PPE** stack.

> **Reality check on the numbers.** The fork is validated on **Xiaomi AX3600 / IPQ8071A**, *not* on
> the EWS377AP v3. Its reported results (NSS ECM NAT/PPPoE offload, NSS SQM at dramatically lower host
> CPU) are **AX3600 figures, not an EWS377 benchmark** — do not represent them as such. The EWS377's
> IPQ8072A part is close enough that the NSS block is a *plausible* target, but every EWS377-specific
> piece below is validated independently.

### Prerequisites

- Phases 0–6 working: `ap-hk07.dts` boots, ath11k calibrates, sysupgrade + failsafe proven.
- A sacrificial unit with the OEM slot still intact for rollback.

### Build

- Add the NSS-EDMA feed/fork on top of the same board port (reuse `ap-hk07.dts` + the extracted BDF).
- Enable the NSS firmware/driver packages and the EDMA/PPE + ECM offload for the IPQ807x target.
- Produce it as a **separate image**, flashed to a **non-OEM slot**, never over the last known-good.

### EWS377-specific validation gates (each must pass on real hardware)

1. **NSS firmware brings up** on the EWS377's exact IPQ8072A revision — NSS cores load, no firmware
   mismatch, `dmesg` clean.
2. **EDMA/PPE binds to this board's Ethernet** — the port topology from the OEM DTS (PHY addrs, uplink
   role) works under the EDMA driver, link + traffic confirmed.
3. **ECM offload actually engages** — NAT/PPPoE/bridge flows show accelerated (offloaded) connections,
   not silent host-path fallback. Verify host CPU drops under load.
4. **ath11k Wi-Fi offload** interoperates with the extracted `board-2.bin`/caldata — no regression vs.
   the pre-offload bring-up, TX power/reg-domain still sane.
5. **SQM under NSS** behaves (if used) — shaping accurate, no offload-vs-shaper conflict.
6. **Stability under sustained load + thermals** — NSS paths don't wedge; watchdog/failsafe still work.

### Decision rule

Treat NSS offload as **experimental** until gates 1–4 pass on the EWS377 itself. If NSS won't bind
cleanly to this board's Ethernet or radios, ship the same port with offload disabled (correct but
slower) rather than an unvalidated offload path — then keep debugging NSS. Record actual EWS377
measurements in `benchmarks/`; never reuse AX3600 figures as a stand-in.

---

## Effort / risk summary

| Phase | Effort | Risk |
|---|---|---|
| 0 Secure boot check | low | **project-ending if fused** |
| 1 Harvest | low | none (read-only) |
| 2 TFTP bring-up | low | none (RAM only) |
| 3 Device tree | medium | low (recoverable) |
| 4 WiFi/BDF | **medium–high** | low (recoverable) |
| 5 Packaging/install | medium | medium (flash writes) |
| 6 Upstream | medium | none |
| 7 Enable/validate NSS offload | **high** | medium (experimental; if NSS won't bind, ship with offload off) |

Realistic total for someone comfortable with OpenWrt device porting: **a few focused weekends** if
secure boot is open and a usable BDF is obtainable.

## Biggest shortcut

Before writing `ap-hk07.dts`, check the current OpenWrt tree for an **already-supported IPQ8072A 4×4
sibling** (EnGenius / Edgecore / Cambium share reference designs). An existing `.dts` + working
`board-2.bin` collapses most of Phases 3–4 into copy-and-adjust.
