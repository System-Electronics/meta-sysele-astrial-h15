# Astrial H15 customizations
# System Electronics

# Standard, lsb_release/os-release-compatible place for the release tag,
# same value already used for /opt/sysele/share/build-info (SYSELE_BSP_VERSION,
# the pushed tag in CI, "unreleased" on a local build). ROOTFS_POSTPROCESS_COMMAND
# runs after /etc/os-release already exists, so this only appends a field.
ROOTFS_POSTPROCESS_COMMAND += "sysele_write_os_release; "

sysele_write_os_release () {
    echo 'ASTRIAL_VERSION="${SYSELE_BSP_VERSION}"' >> ${IMAGE_ROOTFS}${sysconfdir}/os-release
}

# System Electronics board tools. Development image only: a production image
# leaves this line out and the whole /opt/sysele tree disappears with it.
IMAGE_INSTALL:append = " sysele-tools evtest sysele-dsi-detection sysele-dsi-touch-test"

# IMAGE_BOOT_FILES puts swupdate-image in the boot partition without
# declaring it: building core-image-hailo-dev alone fails on a clean tree.
# Not circular: swupdate-image only produces ext4.gz and doesn't go through
# do_image_wic.
do_image_wic[depends] += "swupdate-image:do_image_complete"

# With A/B fallback enabled, two more things are needed and are pulled in
# automatically: slot-sync, which reorders the list after a crash, and a
# daemon that opens /dev/watchdog. Without the daemon, no failed boot is
# ever counted and the fallback never triggers. Disabled, this line adds nothing.
IMAGE_INSTALL:append = " ${@bb.utils.contains('SYSELE_SCU_AB', '1', 'sysele-slot-sync watchdog', '', d)}"
