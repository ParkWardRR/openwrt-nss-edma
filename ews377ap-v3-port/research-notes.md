# Research notes — community / secure-boot / prior art

Findings from OpenWrt community sources relevant to this port (2026-09-03).

> **STATUS: confirmed (2026-09-06).** The secure-boot prior below proved correct — a direct fuse read
> on the unit showed **secure boot is NOT fused**; custom images boot. Port is complete and validated.

## Secure boot on IPQ807x (the go/no-go)

- **robimarko** (core OpenWrt IPQ maintainer), on the IPQ807x investigation thread: *"I would bet that
  it does not have secure boot. Secure boot has been available in both IPQ806x and IPQ40xx and nobody
  used it."* → strong prior that IPQ807x OEMs generally don't fuse secure boot.
- **Ansuel** counters with a real counter-example: Netgear EX7700 (IPQ40xx) *did* fuse it and bricked
  a unit trying to flash an unlocked u-boot. → not universal; still verify on the EWS377 at u-boot
  before flashing anything to the boot chain.
- Our own evidence points the same way: stock u-boot `bootipq` loads a FIT that is only MD5/CRC
  checked, and the OEM rootfs does no dm-verity/signature check. Definitive check is still the u-boot
  fuse read / unsigned `bootm` test (Phase 0).

## Prior art / collaborators

- **No existing EnGenius IPQ807x OpenWrt port** exists. On "Adding OpenWrt support for Senao-like
  devices", user **cybrnook** reports having **EWS357 (v1/v3) and EWS377 (v1/v3)** hardware and wanting
  a port ("the hardware is here"). Potential collaborator / second test unit.
- Closest in-tree analogs already supported: Aliyun **AP8220** (IPQ8071, 2.5G on port@6/uniphy2 — our
  Ethernet template), Netgear **WAX218/WAX620**, Dynalink DL-WRX36, EnGenius-adjacent TP-Link
  EAP660HD. The Netgear WAX218 bootlog is cited as covering EWS377AP v3 / ECW230 v3 (same IPQ8072a,
  512 MB RAM, 256 MiB NAND, serial 115200 8N1).

## Confirmed hardware sizing

- RAM **512 MB**, NAND **256 MiB**, serial **115200 8N1** (community bootlog + our DTB extraction agree).

## Sources

- OpenWrt forum: "IPQ807x SoC Investigation / Status [WIP]"
- OpenWrt forum: "Adding OpenWrt support for Senao like Devices"
- OpenWrt forum: "OpenWrt support for WAX218"
- In-tree: `ipq8071-ap8220.dts`, `qualcommax` target
