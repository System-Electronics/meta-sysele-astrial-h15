# The daemon opens /dev/watchdog and feeds it. Only in the image when A/B
# fallback is enabled (see core-image-hailo-dev.bbappend); without it,
# watchdog.open_timeout would reset even a healthy slot.
#
# Starts at S98, hailo_linux_init.sh at S99: the slot is declared good once
# the daemon is present.
INITSCRIPT_PARAMS:${PN} = "start 98 2 3 4 5 . stop 85 0 6 ."
