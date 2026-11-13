# Fallback to the other slot: wired up, disabled.
#
# Hailo describes a single slot and sets boot_max_retries to 0xFF, which
# disables falling back to another image. The defaults here (0x00000000,
# 0xFF, 0) keep today's behavior: both generated json files match Hailo's.
#
# Enabling it means giving these three variables real values, e.g.
# 0x00078000, 0x02, 2: the lists become A,B,A and B,A,B, the same pattern
# validated on QBAstrial. The rest follows (sysele-slot-sync, watchdog,
# hailo_linux_init ordering).
#
# One manual step remains: actually programming slot B, since
# program_spi_flash.sh only writes the image to 0x0.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Defaults live in conf/machine/astrial-h15.conf, so the image sees them too
# and there is a single switch.

SRC_URI:append:astrial-h15 = " file://scu_bl_cfg_a.json.in file://scu_bl_cfg_b.json.in"

# do_install, not do_configure: that's where the json is turned into binary.
do_install:prepend:astrial-h15() {
    for slot in a b; do
        sed -e "s|@FALLBACK_OFFSET@|${SYSELE_SCU_FALLBACK_OFFSET}|g" \
            -e "s|@BOOT_RETRIES@|${SYSELE_SCU_BOOT_RETRIES}|g" \
            -e "s|@LAST_VALID_DESC@|${SYSELE_SCU_LAST_VALID_DESC}|g" \
            "${WORKDIR}/scu_bl_cfg_$slot.json.in" > "${WORKDIR}/scu_bl_cfg_$slot.json"
    done
}

do_install[vardeps] += "SYSELE_SCU_FALLBACK_OFFSET SYSELE_SCU_BOOT_RETRIES SYSELE_SCU_LAST_VALID_DESC"
