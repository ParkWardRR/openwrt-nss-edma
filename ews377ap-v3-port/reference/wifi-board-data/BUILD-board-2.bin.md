# Building the ath11k board-2.bin for the EWS377AP v3

**Board id is known: `0x290`** (both OEM DTBs set `qcom,board_id = <0x290>`; the OEM `senaoBDF.note`
maps 0x290 → `bdwlan.b290`, shared with ECW230v3 — same hk07 board). Source blob: `bdwlan.b290-ecw230v3`.

Mainline ath11k looks board data up by a full board-id string it prints at probe, e.g.:

    ath11k ... qmi_board_id 0x290 ...
    ath11k ... board_id 0x290 chip_id 0x0

So on first boot, read that line over UART/serial, then build a container matching it:

    # ath11k-bdencoder from qca-swiss-army-knife / ath11k-firmware tools
    cp bdwlan.b290-ecw230v3 bdwlan.b290
    cat > board.json <<'JSON'
    [ { "names": [ "bus=ahb,qmi-chip-id=0,qmi-board-id=656,variant=EnGenius-EWS377AP-v3" ],
        "data": "bdwlan.b290" } ]
    JSON
    ath11k-bdencoder -o board-2.bin board.json     # 656 == 0x290

Then drop `board-2.bin` into `package/firmware/ipq-wifi/` as `board-engenius_ews377ap-v3.<variant>`
and set the DTS `qcom,ath11k-calibration-variant` to the same `variant=` string.

NOTE: qmi-chip-id and the exact name format must be confirmed from the boot log — 0x290 is certain,
the surrounding string is the only unknown. That's why this isn't pre-generated here.
