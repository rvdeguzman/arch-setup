# MiniBook X migration audit

Read-only inspection of the currently installed system. No packages, services, boot entries, or live configuration were changed. This report is the only newly created file. Intended replacement: plain Arch Linux with Hyprland.

## Scope and limits

This records hardware, active drivers/services, configuration, package metadata, and relevant logs. It does not establish that every physical function works: keys, touchscreen accuracy, folding/tablet mode, suspend/resume, Bluetooth pairing, microphone, webcam, and external displays still need manual tests. No wireless passwords, Tailscale authentication state, disk-encryption secrets, or application credentials were collected.

## Hardware and kernel baseline

- CHUWI MiniBook X, Intel N100 (4 CPUs).
- Firmware: DNN20 V2.22, BIOS date 06/12/2024.
- UEFI boot; Secure Boot currently disabled.
- Intel UHD GPU, PCI 8086:46d1, active driver `i915`.
- Intel AX101 Wi-Fi, PCI 8086:54f0, subsystem 8086:0244, driver `iwlwifi`/`iwlmvm`.
- Intel Bluetooth USB 8087:0026, `btusb`/`btintel`; firmware loading succeeds in this boot's logs.
- Audio controller 8086:54c8, active PCI driver `snd_hda_intel`, Realtek ALC269VC codec.
- Goodix 9110 touchscreen, `goodix_ts` driver.
- Touchpad: `XXXX0000:05 0911:5288 Touchpad`, I2C HID. Distribution hwdb already supplies resolution hints in `/usr/lib/udev/hwdb.d/60-evdev.hwdb`; no custom local hwdb file found.
- Two `mxc4005` accelerometers currently exposed through IIO.
- Webcam USB 1b0a:2bc9, `uvcvideo`; video nodes and PipeWire camera devices present.
- Running kernel: `7.0.9-arch2-1`. Installed `linux` package: `7.2.3.arch1-3`. The current main Limine entry still labels its kernel as 7.0.9. Do not treat the installed kernel as a tested hardware baseline; audit why entries differ separately before relying on the current install as a recovery reference.
- Kernel taint value 0; no DKMS/custom module package or extra module directory identified by this audit.

## 1. Boot, panel, desktop, and touch rotation

These are distinct settings, not a single rotation fix.

### Bootloader

`/boot/limine.conf` contains:

```ini
interface_rotation: 90
```

The active UEFI loader is Limine. It has a normal EFI entry and fallback EFI path. The current loader identifies as 12.5.1 while the installed package is 12.8.0: installed package versions alone do not establish deployed bootloader versions.

### Kernel panel orientation

`/etc/default/limine` and the actual running kernel command line include:

```text
video=DSI-1:panel_orientation=right_side_up
```

This is a hardware setting worth carrying forward. Do not copy the entire existing kernel command line: its encryption partition references, root mapping, filesystem/subvolume options, and UKI paths are specific to the current installation.

### Hyprland display

`~/.config/hypr/monitors.conf` currently contains:

```ini
env = GDK_SCALE,2
monitor=,1920x1200,auto,1.67,bitdepth,8,transform,3
```

Live output from Hyprland:

- Connector: `DSI-1`.
- Native mode and only advertised mode: `1200x1920@50.00Hz`.
- Transform: `3` (270-degree desktop transform).
- Scale: `1.67`.
- Format: `XRGB8888`.
- No reported Hyprland configuration errors.

The configured mode text differs from the native mode reported by the live output. For a clean configuration, validate use of the native/preferred mode rather than assuming the literal `1920x1200` request is the correct physical mode. Scope the rotation to `DSI-1`: the current blank-connector rule is a catch-all and could incorrectly rotate an external monitor. Scale and `GDK_SCALE` are user preferences, not hardware-driver requirements.

### Touchscreen

`~/.config/hypr/input.conf` contains:

```ini
input {
  touchdevice {
    transform = 3
    output = DSI-1
  }
}
```

Carry this forward with the desktop rotation and verify touch accuracy in all four corners. Touchscreen and display transforms must be validated together.

### Kernel console

Live framebuffer: `i915drmfb`, 1200x1920, `fbcon/rotate` reports 0. No explicit `fbcon=rotate:` argument was found. Do not assume the kernel console and early disk-unlock prompt have the right orientation merely because the boot menu and desktop do; visually test those stages on the replacement install.

## 2. Tablet-mode support: important non-stock component

Installed package:

- `minibook-support-git` version `1.3.1.r14.b4984c9-1`.
- Upstream: https://github.com/petitstrawberry/minibook-support
- Cached source revision: `b4984c969d9a49c52f7d6e2ffa1138c776ce01c0`.
- Installed package files pass `pacman -Qkk` (0 altered files).

Services currently running:

- `keyboardd.service`: enabled; creates a virtual keyboard and controls event passthrough.
- `tabletmoded.service`: enabled; determines tablet mode using the two accelerometers and controls the keyboard/trackpad services.
- `trackpadd.service`: running, although not independently enabled. It is required by `tabletmoded.service`.

Hyprland sees `MiniBookSupport Virtual Keyboard`, `MiniBookSupport Virtual Trackpad`, and `MiniBookSupport Virtual Switch`.

The cached source for the installed revision confirms that `tabletmoded` instantiates the second `mxc4005` accelerometer at address `0x15` when missing. Current sysfs and boot logs show the second device on I2C bus 0. This is an important reason not to discard the package as an unused background daemon.

This package is tablet-mode/input-disable support, not proof of desktop autorotation. No separate desktop autorotation service was identified. Current desktop/touch rotation is static.

Packaging caveat: the cached AUR install script references nonexistent/obsolete `moused.service`, whereas the installed files and tablet service use `trackpadd.service`. Review/fix packaging and explicit service activation before rebuilding; do not blindly execute the cached installer. Reinstallation should preserve the package's function, with reviewed current source, rather than automatically trusting a moving `-git` revision.

## 3. Function keys and brightness

Current media bindings are sourced from:

`~/.local/share/omarchy/default/hypr/bindings/media.conf`

They call Omarchy wrappers for:

- Volume, mute, microphone mute.
- Display brightness.
- Keyboard brightness/backlight.
- Touchpad toggle.
- Media playback and output switching.

These bindings must be recreated without Omarchy dependencies. Standard building blocks include `brightnessctl`, `wpctl`, optional `playerctl`, and optional SwayOSD. Keep the Hyprland keys independent of Omarchy launch/menu scripts.

Observed display-backlight device: `/sys/class/backlight/intel_backlight`.

No keyboard-backlight LED/sysfs control was exposed during the audit. Do not assume the generic Omarchy keyboard-backlight bindings actually control this machine: manually test its Fn shortcut and determine whether it is firmware-controlled.

`/etc/modprobe.d/hid_apple.conf` contains `options hid_apple fnmode=2`. This is a generic Omarchy Apple-keyboard setting, not an identified MiniBook fix. The onboard keyboard is an AT translated keyboard; no loaded `hid_apple` module was found. Do not label this file necessary for onboard F-key support.

The power key currently opens the Omarchy system menu in Hyprland, while `/etc/systemd/logind.conf` sets `HandlePowerKey=ignore`. Design both parts together on the replacement so the button is not left unintentionally inert.

## 4. Network and Bluetooth

Current stack is **iwd + systemd-networkd + systemd-resolved**, not NetworkManager. All three are enabled; iwd and networkd were confirmed active. DHCP for wireless is configured in `/etc/systemd/network/20-wlan.network`.

Wi-Fi and Bluetooth firmware load successfully in kernel logs. Bluetooth and Tailscale system services are enabled and active. No custom Wi-Fi driver or special local driver option was identified.

A fresh installation can retain this stack or use NetworkManager, but must choose/configure a coherent stack rather than unintentionally running competing network managers. Wireless profiles contain secrets and were not copied/read.

Omarchy's `/etc/udev/rules.d/99-wifi-powersave.rules` calls a script under `/home/rv/.local/share/omarchy/bin/`; replace it with independent policy or omit it deliberately. Current Wi-Fi power save is off.

## 5. Audio, GPU, camera

- PipeWire and WirePlumber are running.
- Built-in analog stereo output and input are present.
- Camera devices are present in both V4L2 sysfs and PipeWire.
- Installed firmware includes `linux-firmware-intel`, `intel-ucode`, and `sof-firmware`.
- Installed userspace graphics include Mesa and Intel media driver.

No local custom audio codec option was found. Device enumeration is not a speaker, microphone, camera, or Bluetooth functional test.

Suggested baseline: current supported kernel, Intel microcode and firmware, Mesa, PipeWire/WirePlumber, Bluetooth tooling if wanted. Whether an LTS kernel is better must be tested; do not assume it contains all MiniBook fixes.

## 6. Power, idle, lid, suspend

Current components:

- `power-profiles-daemon`: enabled/running; current profile `power-saver`.
- `thermald`: enabled/running, using upstream adaptive mode.
- `hypridle`: running.
- Sleep modes exposed: `s2idle` (selected) and `deep`.
- Intel pstate driver; reported CPU governor `powersave`.

`/etc/udev/rules.d/99-power-profile.rules` calls an Omarchy script for AC/battery changes. Its current script chooses balanced on battery and performance/balanced on AC. Current live profile is not necessarily the same as that policy.

`~/.config/hypr/hypridle.conf` relies on Omarchy for lock, wake, and screensaver commands. Its active listeners start a screensaver and lock; there is no configured automatic idle-suspend listener in this file. Before/after-sleep commands also use Omarchy wrappers. Replace them with a self-contained Hyprlock/Hypridle setup and validate lock-before-suspend.

Lid events currently include Omarchy external-monitor handling. No custom local sleep override was found. No suspend/resume cycle was performed, and the inspected service logs did not supply a useful tested cycle.

Swap currently consists of about 5.7 GiB zram, configured in `/etc/systemd/zram-generator.conf`. No persistent swap device/file or resume kernel arguments were observed. Hibernation must not be assumed configured simply because the kernel advertises support.

`/etc/modprobe.d/disable-usb-autosuspend.conf` contains `options usbcore autosuspend=-1`, but the live usbcore parameter is `2`, and camera/Bluetooth USB runtime-power policy reports `auto`. This file is a generic Omarchy tweak, not an established effective MiniBook fix. Do not blindly preserve or claim it is currently disabling autosuspend.

## 7. Boot/filesystem/session items that are not hardware fixes

Current root/home are Btrfs subvolumes inside an encrypted root mapping; `/boot` is FAT. Limine uses UKIs, mkinitcpio integration, and snapshot menu integration. Recreate these according to the new disk/encryption choices, not by copying identifiers.

Current mkinitcpio override adds Plymouth and `btrfs-overlayfs` snapshot support. A separate drop-in adds `thunderbolt`. These are not established MiniBook requirements. The original initramfs configuration must match any new encryption method.

SDDM currently uses Wayland and autologin to the Omarchy session. For the proposed console-first workflow, SDDM/autologin are not required. A manual Hyprland session still needs correct user-session/environment/portal handling; UWSM is currently installed and used, but is not a MiniBook driver fix.

`~/.config/hypr/hyprland.conf` sources many files under `~/.local/share/omarchy/` and an Omarchy theme. Do not copy it as a self-contained plain-Arch configuration. Extract the desired settings and bindings into independent files.

Generic installed/enabled services such as Docker, printing, and discovery are outside the MiniBook hardware profile and can be separately selected or omitted.

## Warnings, not automatically diagnoses

Kernel logs include firmware ACPI errors, a USB port power-management warning, Goodix dummy-regulator messages, and an early `DSI link not ready` error. The desktop and devices are nevertheless currently enumerated and active. These messages do not by themselves justify speculative kernel arguments or driver changes; correlate them with actual failures if any occur.

## Manual acceptance checklist

Before wiping, record whether these currently work; repeat on the replacement:

1. Limine menu, disk-unlock prompt, console, and Hyprland display orientation.
2. Display scale and touch accuracy at all four corners.
3. Brightness, volume/mute, microphone mute, F keys, and keyboard-backlight shortcut.
4. Fold/unfold behavior: keyboard and trackpad disable/re-enable, with no accidental input lockout.
5. Wi-Fi connection, Bluetooth pairing/audio, Tailscale reconnect after wake.
6. Built-in speaker, microphone, headphone jack, webcam.
7. Lid close/open, suspend/resume, overnight sleep drain, lock-before-suspend.
8. USB-C charging, accessories, and external display behavior.

## Archinstall decisions needed later

The audit does not depend on these choices, but the installation/bootstrap will:

- Bootloader: retaining Limine offers the already-working menu rotation.
- Filesystem and encryption: Btrfs/snapshots versus ext4, encryption method, whether hibernation is required.
- Networking: retain iwd/networkd/resolved or switch to NetworkManager.
- Login/session: console-first manual Hyprland versus display manager.
- Kernel strategy: regular kernel initially versus tested LTS plus fallback.

The user has confirmed Hyprland. Application selection and the Brewfile are separate from this hardware audit; live editor/application configurations are not being promoted to dotfile source of truth.
