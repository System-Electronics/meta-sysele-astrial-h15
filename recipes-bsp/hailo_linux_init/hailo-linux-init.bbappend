# hailo_linux_init.sh writes boot_success_ap_software, telling the SCU
# bootloader that boot succeeded. With A/B fallback enabled it must run last,
# after the watchdog daemon: at S50 it would mark as successful a boot that
# doesn't have user space yet, and a later reset would no longer count as a
# failure.
INITSCRIPT_PARAMS = "${@bb.utils.contains('SYSELE_SCU_AB', '1', 'start 99 5 .', 'start 50 5 .', d)}"
