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
    # scripts/check-config.sh concatena tutti i Kconfig con `cat $(find ...)`. Se uno non
    # finisce con un newline (drivers/pinctrl/hailo/Kconfig, sorgente Hailo), la sua ultima
    # riga si incolla alla prima del file che `find` elenca dopo, e lo script non vede piu'
    # `config INPUT` (drivers/input/Kconfig): "You must add new CONFIG options using
    # Kconfig". L'ordine di `find` dipende dal filesystem, quindi il difetto compare solo
    # su certe macchine (misurato sulla VPS, non sui runner di GitHub).
    find ${S} -name 'Kconfig*' -type f | while read -r f; do
        [ -n "$(tail -c1 "$f")" ] && echo >> "$f"
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

# Secondi che il kernel aspetta che lo user space apra /dev/watchdog, sul solo avvio da eMMC.
SYSELE_WATCHDOG_OPEN_TIMEOUT ?= "60"

do_configure:append() {
    # Solo con il ripiego A/B acceso: uno slot il cui user space non parte deve finire
    # in un reset del watchdog, che il SCU bootloader conta. Il parametro va in
    # bootargs_mmc e basta: bootargs_rw e bootargs_base li usa anche swupdate-image,
    # che scarica per minuti senza aprire il watchdog e verrebbe resettato a meta'.
    if [ "${SYSELE_SCU_AB}" = "1" ] && \
       ! grep -q 'watchdog.open_timeout' ${S}/include/configs/hailo1x_common.h; then
        sed -i 's|\(root=/dev/mmcblk${device_num}p${mmc_rootfs_partition}\)|\1 watchdog.open_timeout=${SYSELE_WATCHDOG_OPEN_TIMEOUT}|' \
            ${S}/include/configs/hailo1x_common.h
        grep -q 'watchdog.open_timeout' ${S}/include/configs/hailo1x_common.h || \
            bbfatal "u-boot: bootargs_mmc non trovato, watchdog.open_timeout non applicato"
    fi
}

do_configure[vardeps] += "SYSELE_SCU_AB SYSELE_WATCHDOG_OPEN_TIMEOUT"
