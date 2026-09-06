# Hardware reference — EWS377AP v3 (`ap-hk07`)

Consolidated facts about the board, boot chain, and flash layout. Sources: live analysis of the
fleet + de-obfuscated stock firmware. Per-device secrets (real MAC/serial) are intentionally omitted.

## SoC / radio

- **SoC:** Qualcomm IPQ807x (IPQ8072A class)
- **WiFi:** 4×4 802.11ax dual-band (tx/rxchainmask `15` on both radios) — same board as ECW230v3 and
  EWS377-FIT. Marketing class "AX3600". FCC + ETSI DFS certified.
- **RAM:** **1 GiB confirmed** on a live unit (u-boot `bdinfo`: DRAM `0x40000000` len `0x40000000`;
  banner "1 GiB"). NOTE: the OEM DTB template and some community bootlogs say 512 MB → likely RAM
  variants exist. Harmless for the DTS: qualcommax reads DRAM size from the bootloader at runtime.
- **NAND:** 256 MiB (OS UBI region starts at NAND `0x01000000`)
- **machid:** `0x8010006` (arch_number); u-boot `2.0.0`, `bootcmd=bootipq`, `bootdelay=5`
- **Board name:** `ap-hk07` (Qualcomm reference-design designator; also the OpenWrt board id used downstream)
- **Serial console:** `ttyMSM0` (blsp1_uart5), 115200n8 (OEM bootargs `console=ttyMSM0,115200,n8`)
- **Firmware IDs:** vendor_id 257 (`0x0101`); product_id — EWS377AP v3 = 282 (`0x011a`),
  EWS377-FIT = 300, ECW230v3 = 284 (all the same silicon; product_id is the only differentiator the
  OEM image check enforces)
- **WiFi board id:** `qcom,board_id = 0x290` → board data `bdwlan.b290`

## Confirmed from firmware analysis (2026-09-02)

- **NAND flash layout** (from the OEM `flash.scr`): the OS UBI region begins at NAND offset
  `0x01000000` (first 16 MB holds SBL / u-boot / APPSBL / env / ART / config); the `wifi_fw` UBI sits
  at `0x07f00000` (len `0x900000`). OpenWrt uses `qcom,smem-part` to read the real table.
- **u-boot env:** `mtd7`, from the OEM `fw_env.config` = `/dev/mtd7 0x0 0x40000 0x20000 2` (256 KB env,
  128 KB sector, 2 copies). A/B slot selection is the u-boot `active_fw` env var (in mtd7).
- **Secure boot (userspace signal):** the OEM rootfs does **no** rootfs signature / dm-verity /
  anti-rollback check, and the image gate is a userspace product_id compare. Consistent with secure
  boot NOT being fused — but the SBL/u-boot fuse is the real arbiter; confirm at the u-boot prompt.

## Stock firmware = QSDK OpenWrt

The FIT sub-images are named `openwrt-ipq-ipq807x-ubi-root.img` (FIT 1.1.30) and
`openwrt-ipq807x-ipq807x_32-ubi-root.img` (ECW230v3 cloud). The stock OS is a downstream QSDK
OpenWrt build → DTS, board files, and partition layout already exist in EnGenius's OpenWrt source.

## Boot chain

- u-boot, `bootcmd=bootipq`, **dual A/B firmware slots** (`active_fw` selects)
- APPSBL (mtd8) holds full compiled u-boot defaults: `bootcmd=bootipq, sn=000000001,
  snextra=00…0, active_fw=0, app_part=0, rootfsname=rootfs`
- FIT boot check is **userspace only** (`/lib/upgrade/check_senao_image_header.sh`, gates on
  vendor_id+product_id) — no observed hardware signature enforcement (⇒ secure boot likely not fused;
  **must still be confirmed at u-boot**, see UART plan Phase 0)

## Flash / MTD map (authoritative — from a live unit's `mtdparts`, NAND 256 MiB)

| mtd | Partition | Offset | Size | Notes |
|---|---|---|---|---|
| 0 | 0:SBL1 | 0x0 | 1M | |
| 1 | 0:MIBIB | 0x100000 | 1M | partition table |
| 2 | 0:QSEE | 0x200000 | 3M | TrustZone |
| 3 | 0:DEVCFG | 0x500000 | 512K | |
| 4 | 0:APDP | 0x580000 | 512K | |
| 5 | 0:RPM | 0x600000 | 512K | |
| 6 | 0:CDT | 0x680000 | 512K | |
| 7 | 0:APPSBLENV | 0x700000 | 512K | **u-boot env** (`fw_setenv` writes here) |
| 8 | 0:APPSBL | 0x780000 | 6784K | u-boot + compiled default env |
| 9 | cert | 0xe20000 | 384K | registration cert |
| 10 | userconfig | 0xe80000 | 1M | |
| 11 | **0:ART** | 0xf80000 | 512K | **RF cal + factory MAC — never write; corruption = real brick** |
| 12 | rootfs_1 | 0x1000000 | 111M | slot A (cloud in OEM layout) |
| 13 | 0:WIFIFW_1 | 0x7f00000 | 9M | wifi fw for slot A |
| 14 | rootfs | 0x8800000 | 111M | slot B (EWS in OEM layout) |
| 15 | 0:WIFIFW | 0xf700000 | 9M | wifi fw for slot B |

OpenWrt reads this table via `qcom,smem-part` (no hand-written offsets). Two 111 MiB rootfs slots =
the A/B dual-boot, selected by the u-boot `active_fw` env var. `setconfig` fields (OEM): field 0 =
9-digit serial; field 19 = `snextra`; fields 6/7/8 = LAN/WAN/WLAN MAC. Real MAC also in ART (mtd11).

## Secure boot — ✅ CONFIRMED NOT fused (definitive, 2026-09-06)

**Direct bootloader fuse read on a live unit confirms the secure-boot fuse is NOT blown** — the
definitive go/no-go answer. This matches every prior signal: open u-boot console
(`setenv`/`saveenv`/`nand read`/`tftpput`/`ping` all work), zero `sec*`/`auth*`/`fuse*` env vars,
CRC32/SHA1-only FIT hashing (no signature), and no userspace dm-verity. **Unsigned images boot →
the OpenWrt port is a GO.** (The initramfs `bootm` RAM test is now just functional bring-up, not a
gate.)

## Access (stock EWS firmware)

- **SSH: port 8822**, user `root`, pw = web admin password (`admin` on reset units). Needs legacy
  `-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa`. Restricted CLI on the login
  channel; the **exec channel** (`ssh -T root@ip 'cmd'`) runs as uid 0.
- Telnet (23): restricted CLI only.
- Web LuCI: login POST `/cgi-bin/luci`, password field = `md5(pw + "\n")`.
- ezMaster-managed units have SSH disabled → web/telnet only until unmanaged.

## u-boot env safety

- Correct edit flow: `setconfig -a 1` (load temp from flash) → `setconfig -a 2 -s <n> -d <val>` →
  commit. **`setconfig -a 5` alone wrote empty stdin to /dev/mtd7 and wiped the env.**
- `fw_setenv`/`fw_printenv` are consistent with `setconfig -g`, but seeding a fresh env from empty
  defaults to `bootcmd=bootp` (netboot) — must be `bootcmd=bootipq`.
- **A valid-but-incomplete env is the trap**: u-boot uses it instead of compiled defaults and
  `bootipq` fails for missing vars. An *erased* env is safe. Recovery: `env default -a; saveenv; reset`.
- Env wipe also clears `ethaddr` → OS falls back to default MAC `00:03:7f:12:3e:87` → unit moves to a
  new DHCP IP (looks bricked, isn't). Check DHCP leases / PoE switch port first.

## Fleet notes

- These units are a deployed production fleet — do all porting on a **sacrificial unit**, never production.
- Siblings share the EnGenius OUI `88:DC:97`.
