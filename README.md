# 🎮 ZenSense — Advanced DualSense Haptics for Linux

![Platform](https://img.shields.io/badge/Platform-Linux-FCC624?style=flat-square&logo=linux&logoColor=black)
![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

**ZenSense** is an advanced automation wrapper and Terminal User Interface (TUI) for Linux that routes game audio to your PlayStation DualSense controller's haptic motors via Bluetooth. 

Experience deep, immersive, and highly customizable rumble in any PC game without a cable!

> 🧠 **Core Credit:** This script is built around the amazing [SAxense](https://github.com/egormanga/SAxense) by **[egormanga](https://github.com/egormanga)** & **Sdore**. Huge thanks to them for the reverse-engineering and C-code that makes the Bluetooth communication possible!

---

## ✨ Key Features

- 🖥️ **Interactive TUI:** A beautiful, pure-Bash terminal interface. Navigate menus, toggle checkboxes, and adjust sliders using your keyboard. No bulky GUI frameworks required!
- 🎛️ **Custom Haptic Builder:** Don't just vibrate—*feel* the game. Build your own profile using built-in SoX audio filters:
  - **Noise Gate:** Mutes background game noise (wind, footsteps) and triggers haptics *only* on loud impacts like gunshots.
  - **Subsonic Filter:** Cuts frequencies below 30Hz to save battery and stop motors from "choking".
  - **Bass Boost:** Amplifies the 75Hz range (the DualSense's sweet spot) for punchy feedback.
  - **Overdrive:** Adds soft clipping for a raw, heavy, mechanical sensation (perfect for Racing & Mech games).
  - **Intensity Slider:** Scale global vibration power from 10% up to 250%.
- 🚀 **Fully Automated Setup:** Automatically detects your OS (Arch, Ubuntu, Fedora), installs missing dependencies, clones `SAxense`, and compiles it with a sleek loading spinner.
- 🔊 **Smart Audio Routing:** Auto-creates a Virtual PipeWire Sink (`DualSense_Haptics`) and strictly links the audio nodes.
- 🔓 **Polkit Auto-Permissions:** Installs a temporary `udev` rule to grant read/write access to the `hidraw` device without requiring a reboot or manual `chmod`.
- 🧹 **Clean Exit:** Safely unloads the virtual sink, restores your terminal cursor, and cleans up when you press `Ctrl+C`.

---

## 🛠️ Prerequisites

- **PipeWire** (Default on modern Linux distros).
- A **DualSense** or **DualSense Edge** controller connected via Bluetooth or USB.

---

## 🚀 Installation & Usage

1. **Download the script:**
   ```bash
   wget https://raw.githubusercontent.com/AndreikaKopeika/ZenSense/refs/heads/main/zensense.sh
   chmod +x zensense.sh
   ```
   *(Alternatively, use `curl -O https://...`)*

2. **Run it:**
   ```bash
   ./zensense.sh
   ```

3. **Select your Haptic Profile** in the interactive menu.

4. **Route the Audio:**
   Open your volume mixer (e.g., `pavucontrol`, KDE/GNOME audio settings) and route your Game's audio output to the **`DualSense_Haptics`** virtual sink.

---

## 🛑 How does it work under the hood?

Here is exactly what this script does to your system during runtime:
1. **Checks Dependencies:** Looks for `pipewire`, `sox`, `make`, `gcc`, `git`, and `pkexec`. Installs them if missing.
2. **Builds SAxense:** Clones the original `SAxense` repo and compiles the C-code with `-O3` optimization.
3. **Discovers Device:** Scans `/sys/class/hidraw` to find the exact node for your connected DualSense.
4. **Fixes Permissions:** Grants temporary `uaccess` via Polkit.
5. **Sets up PipeWire:** Creates a `module-null-sink` and uses `pw-link` to tie the monitor ports to our capture node.
6. **Executes the Pipeline:** Uses `pw-record` to capture audio, pipes it through the requested `sox` filter chain in real-time, and sends the raw byte stream into `SAxense` with zero-latency buffers (`stdbuf -o0`).
