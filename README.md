# 🎮 ZenSense

**ZenSense** is an advanced automation wrapper for Linux that routes game audio to your PlayStation DualSense controller's haptic motors via Bluetooth, giving you deep, immersive rumble without a cable.

> 🧠 **Core Credit:** This script is built around [SAxense](https://github.com/egormanga/SAxense) by **[egormanga](https://github.com/egormanga)** and **[Sdore](https://github.com/Sdore)**. Huge thanks to them for the reverse-engineering and C-code that makes this possible!

## ✨ Features
- 🚀 **Fully Automated:** Installs dependencies (Arch, Ubuntu, Fedora), clones `SAxense`, and builds it automatically.
- 🔊 **Smart Audio Routing:** Automatically creates a Virtual PipeWire Sink (`DualSense_Haptics`) and correctly links audio nodes.
- 🎛️ **Haptic FX (SoX):** Built-in optional Low-Pass filter (250Hz) and bass boost to remove annoying high-pitch buzzing and deliver deep, clean vibrations.
- 🔓 **Polkit Auto-Permissions:** Installs a temporary `udev` rule to grant access to the `hidraw` device without requiring a reboot or manual `chown`.
- 🧹 **Clean Exit:** Safely unloads the virtual sink and restores order when you press `Ctrl+C`.

## 🛠️ Prerequisites
- PipeWire (Default on modern Linux distros)
- A DualSense controller connected via Bluetooth or USB.

## 🚀 Installation & Usage

1. Download the script:
   ```bash
   wget https://raw.githubusercontent.com/AndreikaKopeika/ZenSense/refs/heads/main/zensense.sh
   chmod +x zensense.sh
   ```
2. Run it:
   ```bash
   ./zensense.sh
   ```
3. Open your volume mixer (e.g., `pavucontrol` or system settings) and route your Game's audio output to **DualSense_Haptics**.

## 🛑 How does it work under the hood?
Here is exactly what this script does to your system:
1. Checks for dependencies (like `pipewire`, `sox`, `make`, `gcc`).
2. Clones the original `SAxense` repo and compiles it.
3. Finds your DualSense `hidraw` node (supports both Standard and Edge controllers).
4. Grants read/write access via `pkexec` (Polkit).
5. Uses `pw-record` to capture audio and pipes it through `sox` (if FX is enabled) into `SAxense` with zero-latency buffers (`stdbuf -o0`).
