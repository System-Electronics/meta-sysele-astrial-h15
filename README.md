# Astrial H15 Board User Guide

## System Electronics Hailo-15 Development Platform

- [About this layer](#about-this-layer) - what it is, what it depends on, how it is versioned
- [Building the layer](#building-the-layer) - KAS and the manual route
- [Quickstart](#quickstart) - from a downloaded release to a login prompt
- [Full board guide](docs/board-guide.md) - hardware, programming, first boot, troubleshooting

---

## About this layer

`meta-sysele-bsp` is the System Electronics BSP layer for the **Astrial H15** System on Module. 
It sits on top of Hailo's layers and adds the Astrial machine, its device trees, the
U-Boot and kernel integration, the on-board tools in `/opt/sysele` and the example applications.

### Maintainer

System Electronics. Send patches as pull requests against the default branch, or by
email to Riccardo Fiocchi <hwele05@systemelectronics.com>. Every patch is reviewed before it is merged.

### Dependencies

| Layer | Provides what we append to |
|---|---|
| `core` (poky, `yocto-4.0.35`) | the base |
| `meta-hailo-bsp` | `linux-yocto-hailo`, `hailo-secureboot-assets`, `core-image-hailo-dev` |
| `meta-hailo-media-library` | `libmedialib`, `libgstmedialib`, `expected` |

Yocto release: **kirkstone**. Declared in `conf/layer.conf` through `LAYERSERIES_COMPAT` and
`LAYERDEPENDS`, so a build without those layers fails instead of silently ignoring our bbappends.

The Hailo side comes from the **Hailo Vision Processor Software Package 1.12.0**, which also pins
`meta-hailo` at `kirkstone_v5.3.0` and the kernel at 5.15.32.

### What is in here

| Directory | Contents |
|---|---|
| `conf/machine/` | the `astrial-h15` machine definition |
| `conf/layer.conf` | collection name, dependencies, Yocto compatibility, layer version |
| `kas/` | build configuration: machine, VPU base, cache, poky and meta-hailo pins |
| `recipes-bsp/u-boot/` | U-Boot board support and device tree, including the DDR configuration |
| `recipes-kernel/linux/` | kernel device tree and the patches applied on top of `linux-yocto-hailo` |
| `recipes-sysele/` | `sysele-tools` (the `/opt/sysele` toolbox) and the DSI example applications |
| `recipes-media-library/`, `recipes-gstreamer/` | camera and video pipeline integration |
| `recipes-core/`, `recipes-media-library/` | image and hostname customisations |
| `scripts/` | host-side flashing and TFTP helpers |
| `wic/` | SD card image layout |
| `docs/board-guide.md` | the full board bring-up guide |
| `docs/images/` | pictures used by the README and the guide |

### Branches and versions

Branches are named after the Yocto release they target, as is usual for BSP layers: the name of a
branch says which world it builds for, and stays true for as long as the branch lives.

The live line is `kirkstone`. When it moves on, to a newer Hailo stack or a newer Yocto release, the
line left behind stays as a maintenance branch named after what it carries, for example
`kirkstone-vpu-1.12`.

Releases are tagged `vMAJOR.MINOR.PATCH`:

- **major** is the platform line: kirkstone is 1, scarthgap will be 2. Moving Yocto release breaks
  compatibility for anyone building on top, so it is a major.
- **minor** is a substantial change on our side, which in practice means picking up a new Hailo
  Vision Processor package.
- **patch** is everything else.

A release candidate is `v1.2.0-rc1` and is published as a prerelease.

Automatic builds do **not** create tags. A push to the live branch rewrites a single `continuous`
prerelease, so there is always one stable link to the latest build and no tags pile up. A real
release is created by pushing a `v*` tag by hand.

The version that a board reports is the same tag: `sysele-info` prints it on the `BSP` line, and it
is the first thing to ask for in a support request.

### Licence

MIT, granted by System Electronics BU System Ceramics S.p.a. See `LICENSE`.


## Building the layer

### Building with KAS

1. **Install KAS Build Tool**

```bash
pip3 install "kas==5.3"
```

2. **Clone Main Hailo Repository**

```bash
git clone --branch 1.12.0 --single-branch https://github.com/hailo-ai/meta-hailo-soc.git
cd meta-hailo-soc
```

3. **Clone System Electronics Customization Layer**

```bash
git clone https://github.com/System-Electronics-Org/meta-sysele-astrial-h15.git meta-sysele-bsp
```

4. **Secure Boot Configuration**

The Yocto build requires cryptographic keys for secure boot functionality. Create the customer keypair file:

```bash
# Navigate to the meta layer
cd meta-sysele-bsp
```

**Note**: The `customer_keypair.pem` file is intentionally not included in the repository for security reasons. 

For detailed instructions on generating and configuring secure boot keys, please refer to the **Hailo OS Secure Boot User Guide (hailo_os_secure_boot_user_guide.pdf)** available in the [Hailo Developer Zone](https://hailo.ai/developer-zone/software-downloads/).

**Warning**: Never commit private keys to version control. Keep your cryptographic keys secure and separate from your source code.

5. **Build Using KAS**

```bash
kas build meta-sysele-bsp/kas/astrial-h15.yml
```

This single command will:
- Initialize all required repositories and submodules
- Configure the build environment for Astrial H15
- Set up all necessary layers and dependencies
- Build the complete development image

### Alternative: manual build environment

If you prefer to set up the environment manually without KAS:

1. **Initialize Submodules**

```bash
git submodule update --init --recursive
```

2. **Initialize Build Environment**

```bash
source oe-init-build-env build-astrial-h15
```

3. **Configure Build Settings**

Edit `conf/local.conf`:
```bash
MACHINE = "astrial-h15"
DISTRO = "hailo-distro"
```

---

---

## Quickstart

### What You Need
- Astrial H15 board + compatible CM4/CM5 carrier board
- Ubuntu 20.04+ host computer 
- FTDI USB-to-serial cable, **3V3 signalling, not 5V**
- Ethernet cable
- Internet connection

### Step 1: Download Release Package

Go to [releases page](https://github.com/System-Electronics-Org/meta-sysele-astrial-h15/releases) and download the latest `astrial-h15-yocto-build-<version>.tar.gz` file.

**The archive has no top-level directory**: it unpacks into whatever directory you are in. Give it
one of its own, and keep one directory per release, so you can tell two of them apart later and go
back to an older one without downloading it again:

```bash
mkdir -p ~/astrial/flashing/<version>/release
cd ~/astrial/flashing/<version>
tar -xzf ~/Downloads/astrial-h15-yocto-build-<version>.tar.gz -C release
```

That leaves you with:

```
~/astrial/flashing/
  hailo15_env/                                  the virtual environment from Step 2, shared
  <version>/
    astrial-h15-yocto-build-<version>.tar.gz
    release/
      program_spi_flash.sh                      run the scripts from here
      hailo15_spi_flash_program
      uart_boot_fw_loader
      tftp_server.py
      meta-hailo-soc/build/tmp/deploy/images/astrial-h15/   the images and binaries
```

The scripts find the images through a path relative to themselves, so **run them from inside
`release/`**. From one directory up they will not find anything.

**✓ The tar.gz contains the bootloader, the OS image and all the scripts.**

**One prerequisite is not in it:** the scripts drive the board through Hailo's
`hailo15_board_tools` Python package, which Hailo distributes through the Developer Zone and
we do not redistribute. Step 2 below installs it. Without it `program_spi_flash.sh` stops
before touching the board and tells you so.

### Step 2: Setup Tools and Environment

**Download Hailo board tools:**
Go to [Hailo Developer Zone](https://hailo.ai/developer-zone/software-downloads/) and download the Hailo **Vision Processor** Software Package for Hailo-15H. Extract it and copy the
`hailo15_board_tools-<version>-py3-none-any.whl` file to your release folder.

Take it from the Vision Processor package, not from the Accelerators section: Hailo-10 is a
different device family and ships different board tools. Whatever you download is the right
one if it contains a `hailo15_board_tools-*.whl`.

The version must match the Hailo stack of the release you downloaded, and that changes from one
release to the next. **Check the release notes**: every release lists its stack, the Hailo Vision
Processor package among them, and that is the version of the wheel to take.
`program_spi_flash.sh` warns if the installed one differs, but it cannot fetch the right one for you.

Create it **next to** the release directories, not inside one: it is the same for every release and
you want it to survive when you delete an old one.

```bash
cd ~/astrial/flashing
python3 -m venv hailo15_env
source hailo15_env/bin/activate
pip install /path/to/hailo15_board_tools-<version>-py3-none-any.whl tftpy
sudo apt-get install u-boot-tools
```

Activate it again in every new shell before running any of the scripts:

```bash
source ~/astrial/flashing/hailo15_env/bin/activate
```

The scripts invoke the Hailo tools through `sudo $(which python3)`, so without the environment active
they pick the system Python and fail to find the package.

Configure USB permissions:
```bash
sudo tee /etc/udev/rules.d/11-ftdi.rules > /dev/null << EOF
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6011", GROUP="plugdev", MODE="0664"
EOF
sudo udevadm control --reload-rules
```

### Step 3: Set Up the Hardware

Do all of this with the board **unpowered**. Nothing here needs it on, and the DIP switches are read
at power-on.

1. Mount the Astrial H15 SoM on your carrier board.
2. Connect the FTDI cable to the **40-pin header (40PH)**: GND to pin 6, TX to pin 29, RX to
   pin 7. The cable must be a **3V3** one. A 5V cable can damage the board.
3. Set the carrier board's GPIO voltage to **1.8V**.
4. Set the DIP switches to programming mode: **switch 1 ON, switch 2 OFF**.

![1.8V GPIO Voltage](docs/images/1v8.jpg)

### Step 4: Flash the Bootloader

Power the board now, either from the carrier's own supply or over PoE. Then:

```bash
./program_spi_flash.sh
```

Run it from the directory where you extracted the release, with the virtual environment from Step 2
active. It takes about five minutes and ends with `SPI Flash Programming Completed Successfully`.

If the board is not detected, check the serial device first. **On WSL the USB serial adapter has to
be attached to the Linux side**, with `usbipd`, or `/dev/ttyUSB0` never appears no matter how the
cable is wired.

This writes the whole SPI-NOR set: SCU bootloader and firmware, U-Boot and its device tree, TF-A and
the customer certificate. They are a matched set and are always written together.

When it finishes, **power the board down** and set the DIP switches back to normal boot:
**switch 1 OFF, switch 2 OFF**.

### Step 5: Choose How to Write the System

The bootloader is in place, but the board has no operating system yet. There are two ways to put one
there, and a third for later updates. Pick one now and prepare it with the board still off.

| Route | What you need | Writes to |
|---|---|---|
| **TFTP** | an Ethernet cable and a TFTP server on your host | eMMC or microSD, blank or not |
| **SD card** | a card reader on your host | microSD |
| SWU | a board that already runs Linux | eMMC, as an update rather than a first installation |

TFTP is the one to prefer if you have the cable: it needs no card reader, it writes to a blank eMMC,
and it puts the image where the board boots from in production.

**If you chose TFTP**, connect the Ethernet cable between host and board now, set your host to the
static address `10.0.0.2`, and start the server. The board uses `10.0.0.1`. Full instructions are in
[Setting Up TFTP Server](docs/board-guide.md#setting-up-tftp-server).

> On a PoE carrier the Ethernet cable also carries power. Either power the board from PoE alone, or
> disable PoE on the carrier and keep using its own supply. Do not leave both: decide which one feeds
> the board before plugging the cable in.

**If you chose the SD card**, write it now, from the release you extracted in Step 1 (the image's
name carries the release version, e.g. `core-image-hailo-dev-astrial-h15-v1.2.3.wic`):

```bash
sudo dd if=core-image-hailo-dev-astrial-h15-*.wic \
        of=/dev/sdX bs=4M status=progress
sync
```

Replace `/dev/sdX` with your card reader's device, and check it twice: `dd` writes wherever you point
it. Then insert the card in the carrier.

**SWU** updates a board that already runs Linux; it is not a route for a first installation. The
release ships a `.swu`, SWUpdate is enabled in this board's U-Boot, and the update runs unattended,
launched from the board itself:

```bash
/etc/run_swupdate.sh -b -s 10.0.0.2 -r hailo-update-image-astrial-h15.swu
```

The board records the request, reboots into `swupdate-image`, fetches the file from the TFTP server,
writes it to the eMMC and comes back up on the new system. Nothing needs to be typed at the console
while it runs. `swupdate-image` carries no sshd, so for the few minutes the transfer takes the board
answers ping but refuses port 22: that is the update working, not a board that has gone.

> **An update moves the boot source.** `spl_boot_source` goes from `nor` to `mmc21`, because the
> `.swu` runs `update_fw_env.sh` and moves U-Boot from the SPI-NOR to the eMMC boot partition. It
> happens on every update, not only on a first installation. Afterwards a corrupted eMMC leaves the
> board with no bootloader, where before it would still have come up from the SPI-NOR, which an
> update does not touch.

### Step 6: Power On and Install

Open the serial terminal first, so you see the board from the start:

```bash
sudo picocom --baud 115200 /dev/ttyUSB0
```

Power the board on. U-Boot shows its boot menu.

**If you chose TFTP**, pick the entry that matches where you want the system:

- `Update eMMC (wic) from TFTP`
- `Update SDCARD (wic) from TFTP`

The board downloads the image into RAM and writes it from the first block, so the target does not
need to be formatted or even written before. It takes a few minutes, and the menu comes back when it
is done. Then boot it: `Boot from eMMC` or `Boot from SD Card`.

**If you wrote an SD card**, pick `Boot from SD Card`.

Either way you end at the login prompt:

```
root@astrialh15:~#
```

**Login: root, password root.**

### Step 7: Verify Everything Works

```bash
# Check Hailo driver
lsmod | grep hailo

# Test Hailo hardware
hailortcli scan

# Test Python/AI tools
python3 -c "import hailort; print('PyHailort OK')"

# Test network
ping 8.8.8.8
```

**🎉 Success! Your Astrial H15 is now ready for AI development.**

---

## Full board guide

The step-by-step procedure, with the parts the quickstart summarises: hardware details, the board
tools, TFTP and eMMC programming, validation and troubleshooting.

**[docs/board-guide.md](docs/board-guide.md)**
