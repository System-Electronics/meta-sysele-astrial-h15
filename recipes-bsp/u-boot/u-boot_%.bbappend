FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Add your changes to SRC_URI
SRC_URI += " \
    file://arch/arm/mach-hailo/Kconfig.patch \
    file://arch/arm/dts/Makefile.patch \
    file://board/sysele/astrial-h15/Kconfig \
    file://board/sysele/astrial-h15/Makefile \
    file://include/configs/astrial-h15.h \
    file://arch/arm/dts/astrial-h15.dts \
    file://configs/astrial-h15_defconfig \
"

UBOOT_MACHINE = "astrial-h15_defconfig"

do_configure:prepend() {
    # scripts/check-config.sh concatenates all Kconfig files with
    # `cat $(find ...)`. If one doesn't end with a newline
    # (drivers/pinctrl/hailo/Kconfig, Hailo's source), its last line merges
    # with the first line of the next file in `find`'s order, hiding
    # `config INPUT` (drivers/input/Kconfig): "You must add new CONFIG
    # options using Kconfig". `find`'s order depends on the filesystem, so
    # this only shows up on some machines.
    find ${S} -name 'Kconfig*' -type f | while read -r f; do
        # if, not `[ ] &&`: on the last file the test is false, and bitbake's
        # shell runs with set -e, so a status 1 would fail the whole function.
        if [ -n "$(tail -c1 "$f")" ]; then
            echo >> "$f"
        fi
    done

    # Create directories
    install -d ${S}/board/sysele/astrial-h15
    
    # Copy board files
    cp ${WORKDIR}/board/sysele/astrial-h15/Kconfig ${S}/board/sysele/astrial-h15/
    cp ${WORKDIR}/board/sysele/astrial-h15/Makefile ${S}/board/sysele/astrial-h15/
    
    # Copy config header
    install -d ${S}/include/configs
    cp ${WORKDIR}/include/configs/astrial-h15.h ${S}/include/configs/
    
    # Copy devicetree
    cp ${WORKDIR}/arch/arm/dts/astrial-h15.dts ${S}/arch/arm/dts/
    
    # Copy defconfig
    cp ${WORKDIR}/configs/astrial-h15_defconfig ${S}/configs/
}

# Seconds the kernel waits for user space to open /dev/watchdog, eMMC boot only.
SYSELE_WATCHDOG_OPEN_TIMEOUT ?= "60"

do_configure:append() {
    # Only with A/B fallback enabled: a slot whose user space never starts
    # must end in a watchdog reset, which the SCU bootloader counts. The
    # parameter is added to bootargs_mmc only: bootargs_rw and bootargs_base
    # are also used by swupdate-image, which downloads for minutes without
    # opening the watchdog and would be reset midway through.
    if [ "${SYSELE_SCU_AB}" = "1" ] && \
       ! grep -q 'watchdog.open_timeout' ${S}/include/configs/hailo1x_common.h; then
        sed -i 's|\(root=/dev/mmcblk${device_num}p${mmc_rootfs_partition}\)|\1 watchdog.open_timeout=${SYSELE_WATCHDOG_OPEN_TIMEOUT}|' \
            ${S}/include/configs/hailo1x_common.h
        grep -q 'watchdog.open_timeout' ${S}/include/configs/hailo1x_common.h || \
            bbfatal "u-boot: bootargs_mmc non trovato, watchdog.open_timeout non applicato"
    fi
}

do_configure[vardeps] += "SYSELE_SCU_AB SYSELE_WATCHDOG_OPEN_TIMEOUT"
