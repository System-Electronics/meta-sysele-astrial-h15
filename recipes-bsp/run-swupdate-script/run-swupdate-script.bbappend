# A remote update does not start after a fallback.
#
# The SCU keeps the descriptor index across warm resets. After a fallback
# the index is 1, and set_sw_image.sh remote_update replaces the list
# without resetting it: the SCU then reads descriptor 1 of the new list,
# which is the normal boot entry, and the board restarts without updating.
# Dual mode doesn't hit this because it already sends 99 at the end.
#
# 99 in boot_success_ap_software signals "swupdate completed" and resets
# the index, the same signal hailo_linux_init.sh sends after a dual update.

do_install:append:astrial-h15() {
    [ "${SYSELE_SCU_AB}" = "1" ] || return 0
    sed -i 's|^\(\s*\)echo "Rebooting is about to start..."|\1echo 99 > /sys/devices/soc0/boot_info/boot_success_ap_software 2>/dev/null\n\1echo "Rebooting is about to start..."|' \
        ${D}${targetdir}/run_swupdate.sh
    grep -q 'boot_success_ap_software' ${D}${targetdir}/run_swupdate.sh || \
        bbfatal "run_swupdate.sh: insertion point not found, the descriptor index would not be reset"
}

do_install[vardeps] += "SYSELE_SCU_AB"
