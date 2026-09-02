# Hardware reference — EWS377AP v3 (`ap-hk07`)

Consolidated facts about the board, boot chain, and flash layout. Sources: live analysis of the
fleet + de-obfuscated stock firmware. Per-device secrets (real MAC/serial) are intentionally omitted.

## SoC / radio

- **SoC:** Qualcomm IPQ807x (IPQ8072A class)
- **WiFi:** 4×4 802.11ax — same board as ECW230v3 and EWS377-FIT
- **Board name:** `ap-hk07` (Qualcomm reference-design designator; also the OpenWrt board id used downstream)
- **Firmware IDs:** vendor_id 257 (`0x0101`); product_id — EWS377AP v3 = 282 (`0x011a`),
  EWS377-FIT = 300, ECW230v3 = 284 (all the same silicon; product_id is the only differentiator the
  OEM image check enforces)

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

## Flash / MTD map

| Partition | MTD | Notes |
|---|---|---|
| DEVCFG | mtd3 | device config |
| APPSBLENV | mtd7 | **u-boot env** (`setconfig` / `fw_setenv` write here) |
| APPSBL | mtd8 | bootloader + compiled default env |
| cert | mtd9 | Fit/cloud registration cert (preserved across rootfs flash) |
| **ART** | **mtd11** | **RF calibration + real MAC — corruption = real brick** |
| rootfs (cloud slot) | mtd12 | `rootfs_1` |
| rootfs (EWS slot) | mtd14 | `rootfs`, `active_fw=0` default |

`setconfig` fields: field 0 = 9-digit serial; field 19 = `snextra` (len-20 extended serial);
fields 6/7/8 = LAN/WAN/WLAN MAC. Real MAC also in ART (mtd11).

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
