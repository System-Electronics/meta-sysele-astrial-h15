# The SWU must write to eMMC. Hailo's default is mmcblk0 on this machine,
# which is the SD card, and a single-mode update would write there with no error.
SWUPDATE_DEFAULT_FILESYSTEM_DEVICE:astrial-h15 = "mmcblk1"
