#!/bin/bash
# Build each ap-hk07 SKU as its own single-profile build so each image ships
# only its own ipq-wifi board file (multi-profile builds share one rootfs).
# Usage: build-skus.sh [sku ...]   (default: all three)

cd "${TREE:-$HOME/owrt-build-tree}" || exit 1
TREE=$PWD
OUT=${OUT:-$HOME/release}; rm -rf $OUT; mkdir -p $OUT
for dev in ${@:-ews377ap-v3 ecw230v3 ews377-fit}; do
  sed -i -E "/^CONFIG_TARGET_(qualcommax_ipq807x_)?DEVICE_engenius_/d; /^CONFIG_TARGET_PROFILE=/d; /^CONFIG_DEFAULT_ipq-wifi-engenius/d; /^CONFIG_PACKAGE_ipq-wifi-engenius/d; /^# CONFIG_TARGET_PROFILE/d" .config
  { echo "CONFIG_TARGET_qualcommax_ipq807x_DEVICE_engenius_$dev=y"; echo "CONFIG_PACKAGE_ipq-wifi-engenius_$dev=y"; } >> .config
  make defconfig >/dev/null 2>&1
  grep -q "^CONFIG_TARGET_PROFILE=\"DEVICE_engenius_$dev\"" .config || { echo "PROFILE MISMATCH for $dev"; grep PROFILE .config; exit 1; }
  grep "^CONFIG_TARGET_PROFILE\|^CONFIG_PACKAGE_ipq-wifi-engenius" .config
  make -j9 > "$TREE/build-$dev.log" 2>&1
  B=bin/targets/qualcommax/ipq807x
  cp $B/openwrt-qualcommax-ipq807x-engenius_$dev-* $B/openwrt-qualcommax-ipq807x-engenius_$dev.manifest $OUT/
  rm -rf /tmp/v_$dev && mkdir /tmp/v_$dev && (cd /tmp/v_$dev && tar xf $TREE/$B/openwrt-qualcommax-ipq807x-engenius_$dev-squashfs-sysupgrade.bin && $TREE/staging_dir/host/bin/unsquashfs4 -q -d rootfs sysupgrade-*/root >/dev/null 2>&1; echo "$dev board-2.bin: $(sha256sum rootfs/lib/firmware/ath11k/IPQ8074/hw2.0/board-2.bin | cut -c1-16)")
done
echo "ALL-DONE: images in $OUT"
