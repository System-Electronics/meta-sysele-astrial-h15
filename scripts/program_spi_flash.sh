#!/bin/bash

# Astrial H15 SPI Flash Programming Script
# System Electronics - Hailo-15 Development Platform
# 
# This script programs the SPI flash memory with the necessary bootloader components
# for the Astrial H15 board. Run this script after building the Yocto image.
#
# Prerequisites:
# - Hailo-15 board tools installed in virtual environment (see README, "Setup
#   Tools and Environment"). They are NOT part of this archive: the wheel comes
#   from the Hailo Vision Processor Software Package.
# - Board connected via USB-Serial (typically /dev/ttyUSB0)
# - DIP switches set to programming mode (1=ON, 2=OFF)
# - Built Yocto image artifacts available
# - Root privileges (sudo) for serial port access
#
# Usage: ./program_spi_flash.sh [serial_device] [--with-b-slot]
# Example: ./program_spi_flash.sh /dev/ttyUSB0
#          ./program_spi_flash.sh /dev/ttyUSB0 --with-b-slot
#
# --with-b-slot also writes the second copy of the firmware, which the SCU
# bootloader falls back to when the first one does not start. Only useful with a
# layer built with SYSELE_SCU_FALLBACK_OFFSET set: without that, the descriptor
# list names one slot and the second copy is never read. Doubles the time.

set -e

echo "WARNING: This script requires root permissions for serial port access."

# Default serial device, and the B slot off unless asked for
SERIAL_DEVICE=/dev/ttyUSB0
WITH_B_SLOT=0
for arg in "$@"; do
    case "$arg" in
        --with-b-slot) WITH_B_SLOT=1 ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *) SERIAL_DEVICE="$arg" ;;
    esac
done

# Version of hailo15_board_tools that matches the Hailo stack this layer builds
# against. Tracks the meta-hailo refspec in kas/astrial-h15-vpu-base.yml, so it
# changes when that does.
HAILO_BOARD_TOOLS_VERSION="1.12.0"

# The two programs below are thin wrappers around the hailo15_board_tools Python
# package, and they run under the interpreter that "which python3" resolves to.
# Check that one, not any other, or the error surfaces much later as a bare
# ModuleNotFoundError from inside sudo.
PYTHON_BIN=$(which python3)

if ! "$PYTHON_BIN" -c "import hailo15_board_tools" >/dev/null 2>&1; then
    cat >&2 <<EOF

ERROR: the Python package hailo15_board_tools is not available to $PYTHON_BIN

This package is not shipped in this archive. It is part of the Hailo Vision
Processor Software Package, which you download from the Hailo Developer Zone:

    https://hailo.ai/developer-zone/software-downloads/

Take hailo15_board_tools-${HAILO_BOARD_TOOLS_VERSION}-py3-none-any.whl out of it and install it:

    python3 -m venv hailo15_env
    source hailo15_env/bin/activate
    pip install hailo15_board_tools-${HAILO_BOARD_TOOLS_VERSION}-py3-none-any.whl
    pip install tftpy

Then run this script again with that virtual environment active. If it is
already active, check that "which python3" points inside it.

EOF
    exit 1
fi

INSTALLED_BOARD_TOOLS=$("$PYTHON_BIN" -c     "from importlib.metadata import version; print(version('hailo15_board_tools'))" 2>/dev/null     || echo "unknown")

if [ "$INSTALLED_BOARD_TOOLS" != "$HAILO_BOARD_TOOLS_VERSION" ]; then
    echo "WARNING: hailo15_board_tools is $INSTALLED_BOARD_TOOLS, this release expects $HAILO_BOARD_TOOLS_VERSION" >&2
    echo "         Flashing may still work, but the two are not known to match." >&2
fi

# Try to find build directory - check current directory first, then common locations
if [ -f "hailo15_uart_recovery_fw.bin" ]; then
    BUILD_DIR="."
elif [ -d "../build/tmp/deploy/images/astrial-h15" ]; then
    BUILD_DIR="../build/tmp/deploy/images/astrial-h15"
elif [ -d "build/tmp/deploy/images/astrial-h15" ]; then
    BUILD_DIR="build/tmp/deploy/images/astrial-h15"
elif [ -d "meta-hailo-soc/build/tmp/deploy/images/astrial-h15" ]; then
    BUILD_DIR="meta-hailo-soc/build/tmp/deploy/images/astrial-h15"
elif [ -d "../../build/tmp/deploy/images/astrial-h15" ]; then
    BUILD_DIR="../../build/tmp/deploy/images/astrial-h15"
else
    BUILD_DIR="build/tmp/deploy/images/astrial-h15"  # Default fallback
fi

echo "========================================"
echo "Astrial H15 SPI Flash Programming"
echo "========================================"
echo "Serial Device: $SERIAL_DEVICE"
echo "Build Directory: $BUILD_DIR"
echo "Board Tools: $INSTALLED_BOARD_TOOLS"
echo ""

# Check if build artifacts exist
if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: Build directory not found: $BUILD_DIR"
    echo ""
    echo "Searched in the following locations:"
    echo "  - . (current directory)"
    echo "  - ../build/tmp/deploy/images/astrial-h15"
    echo "  - build/tmp/deploy/images/astrial-h15"  
    echo "  - meta-hailo-soc/build/tmp/deploy/images/astrial-h15"
    echo "  - ../../build/tmp/deploy/images/astrial-h15"
    echo ""
    echo "Please ensure you have:"
    echo "1. Set up the Yocto build environment"
    echo "2. Run 'bitbake core-image-hailo-dev' successfully"
    echo "3. Execute this script from the correct directory"
    exit 1
fi

# Check if serial device exists
if [ ! -e "$SERIAL_DEVICE" ]; then
    echo "Error: Serial device not found: $SERIAL_DEVICE"
    echo "Please check your USB-Serial connection"
    exit 1
fi

load_recovery_firmware() {
    echo "Starting UART boot firmware loader, requiring sudo permissions..."
    sudo "$PYTHON_BIN" ./uart_boot_fw_loader \
        --serial-device-name "$SERIAL_DEVICE" \
        --firmware "$BUILD_DIR/hailo15_uart_recovery_fw.bin"
}

# $@ are extra options: --b-image writes the second copy, every section from
# 0x8000 up shifted by 0x78000, which is the offset the B descriptor names.
program_flash() {
    sudo "$PYTHON_BIN" ./hailo15_spi_flash_program \
        --scu-bootloader "$BUILD_DIR/hailo15_scu_bl.bin" \
        --scu-bootloader-config "$BUILD_DIR/scu_bl_cfg_a.bin" \
        --scu-firmware "$BUILD_DIR/hailo15_scu_fw.bin" \
        --uboot-device-tree "$BUILD_DIR/u-boot.dtb.signed" \
        --bootloader "$BUILD_DIR/u-boot-spl.bin" \
        --bootloader-env "$BUILD_DIR/u-boot-initial-env" \
        --customer-certificate "$BUILD_DIR/customer_certificate.bin" \
        --uart-load \
        --serial-device-name "$SERIAL_DEVICE" \
        --uboot-tfa "$BUILD_DIR/u-boot-tfa.itb" \
        "$@"
}

load_recovery_firmware

if [ $? -ne 0 ]; then
    echo "Error: UART boot firmware loader failed"
    exit 1
fi

echo "Programming SPI flash memory, requiring sudo permissions..."
program_flash

if [ $? -eq 0 ]; then
    if [ "$WITH_B_SLOT" = "1" ]; then
        echo ""
        echo "Programming the B slot (second copy, offset +0x78000)..."
        # We don't know whether the recovery firmware stays loaded after the
        # first programming pass: if the second one doesn't start, reload it
        # and retry, instead of failing the whole run and forcing a restart
        # from scratch.
        if ! program_flash --b-image; then
            echo "Retrying after reloading the recovery firmware..."
            load_recovery_firmware
            program_flash --b-image
        fi
        echo "B slot programmed"
    fi

    echo ""
    echo "========================================"
    echo "SPI Flash Programming Completed Successfully!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "1. Power down the board"
    echo "2. Set DIP switches to normal boot mode (1=OFF, 2=OFF)"
    echo "3. Power on the board to verify U-Boot menu appears"
    echo ""
    if [ "$WITH_B_SLOT" = "1" ]; then
        echo "The B slot holds a copy of the firmware. The SCU bootloader uses it only"
        echo "if the descriptor list says so, which needs SYSELE_SCU_FALLBACK_OFFSET set"
        echo "when the layer is built."
        echo ""
    fi
else
    echo "Error: SPI flash programming failed"
    echo "Please check connections and try again"
    exit 1
fi
