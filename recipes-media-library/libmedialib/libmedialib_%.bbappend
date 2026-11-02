FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://0001-resolve-dual-camera-sensors-from-media-graph.patch \
    file://0002-carry-sensor-id-into-the-gst-mode-profile.patch \
    file://0003-do-not-require-custom-rhs1-in-sdr.patch \
    file://0004-single-camera-3a-config-as-sensor-0.patch \
"

# libmedialib now uses libmediactl directly to resolve the sensor connected
# to each CSI receiver from the runtime media graph.
DEPENDS:append = " v4l-utils"
