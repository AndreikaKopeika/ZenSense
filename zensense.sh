#!/usr/bin/env bash
#
# ==============================================================================
# ZenSense - Haptics Over Bluetooth
# A universal tool to route game audio to DualSense haptic motors via Bluetooth.
# 
# Script by: Kopeika
# Core SAxense C code by: egormanga & Sdore
# ==============================================================================

set -e # Exit immediately if a command exits with a non-zero status

# --- UI & Colors ---
C_RST='\033[0m'
C_BOLD='\033[1m'
C_BLUE='\033[1;34m'
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'
C_MAGENTA='\033[1;35m'

print_info()    { echo -e "${C_BLUE}ℹ ${C_RST} ${C_BOLD}$1${C_RST}"; }
print_success() { echo -e "${C_GREEN}✔ ${C_RST} ${C_BOLD}$1${C_RST}"; }
print_error()   { echo -e "${C_RED}✖ ${C_RST} ${C_BOLD}$1${C_RST}"; }
print_warn()    { echo -e "${C_YELLOW}⚠ ${C_RST} ${C_BOLD}$1${C_RST}"; }
print_prompt()  { echo -ne "${C_MAGENTA}⚙ ${C_RST} ${C_BOLD}$1${C_RST}"; }

# ASCII Banner
show_banner() {
    clear
    echo -e "${C_CYAN}"
    cat << "EOF"
  ______           _____                     
 |___  /          / ____|                    
    / / ___ _ __ | (___   ___ _ __  ___  ___ 
   / / / _ \ '_ \ \___ \ / _ \ '_ \/ __|/ _ \
  / /_|  __/ | | |____) |  __/ | | \__ \  __/
 /_____\___|_| |_|_____/ \___|_| |_|___/\___|
                                                                                                                
EOF
    echo -e "${C_RST}${C_BOLD}     DualSense Haptics Over Bluetooth     ${C_RST}"
    echo -e "${C_CYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RST}"
    echo -e "   🚀 Scripted by: ${C_GREEN}Kopeika${C_RST}"
    echo -e "   🧠 Core SAxense by: ${C_YELLOW}egormanga & Sdore${C_RST}\n"
}

# --- Spinner Function ---
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# --- Global State Variables ---
MODULE_ID=""
BIN_PATH=""
DS_DEV=""
USE_EFFECTS=false

# --- Cleanup Handler ---
cleanup() {
    echo -e "\n"
    print_info "🧹 Shutting down ZenSense cleanly..."
    if [ -n "$MODULE_ID" ]; then
        pactl unload-module "$MODULE_ID" 2>/dev/null || true
        print_success "Virtual sink (DualSense_Haptics) removed."
    fi
    print_success "Goodbye!"
    exit 0
}
trap cleanup INT TERM EXIT

# --- Task 1: Universal Dependency Check ---
check_dependencies() {
    local MISSING_CMDS=()
    for cmd in git gcc make pw-record pactl stdbuf sox grep sed pkexec pw-link; do
        if ! command -v "$cmd" &> /dev/null; then
            MISSING_CMDS+=("$cmd")
        fi
    done

    if [ ${#MISSING_CMDS[@]} -ne 0 ]; then
        print_warn "Missing required commands: ${MISSING_CMDS[*]}"
        print_info "Detecting Package Manager..."

        if command -v pacman &> /dev/null; then
            print_info "Arch Linux detected. Installing dependencies..."
            sudo pacman -S --needed base-devel pipewire libpulse coreutils sox git polkit grep sed
        elif command -v apt-get &> /dev/null; then
            print_info "Debian/Ubuntu detected. Installing dependencies..."
            sudo apt-get update
            sudo apt-get install -y build-essential pipewire pulseaudio-utils coreutils sox libsox-fmt-all git policykit-1
        elif command -v dnf &> /dev/null; then
            print_info "Fedora detected. Installing dependencies..."
            sudo dnf install -y gcc make pipewire pulseaudio-utils coreutils sox git polkit
        else
            print_error "Unsupported package manager. Please install missing dependencies manually: ${MISSING_CMDS[*]}"
            exit 1
        fi
        print_success "Dependencies resolved."
    else
        print_success "All system dependencies are installed."
    fi
}

# --- Task 2: Auto-Download & Build SAxense ---
prepare_saxense() {
    if [ ! -d "SAxense" ] &&[ ! -f "SAxense.c" ]; then
        print_info "SAxense repository not found locally."
        print_info "Cloning from https://github.com/egormanga/SAxense.git ..."
        git clone https://github.com/egormanga/SAxense.git ./SAxense || { print_error "Failed to clone repository."; exit 1; }
        print_success "Repository cloned."
    fi

    # СТРОГАЯ ПРОВЕРКА НА ФАЙЛ (исключает попытку выполнить папку)
    if [ -f "./SAxense/SAxense" ] &&[ ! -d "./SAxense/SAxense" ]; then
        BIN_PATH="./SAxense/SAxense"
    elif [ -f "./SAxense" ] && [ ! -d "./SAxense" ]; then
        BIN_PATH="./SAxense"
    fi

    # Компилируем, если не нашли
    if [ -z "$BIN_PATH" ]; then
        print_info "Building SAxense from source..."
        if [ -f "./SAxense/Makefile" ]; then
            (make -C SAxense > /dev/null 2>&1) & spinner $!
            BIN_PATH="./SAxense/SAxense"
        elif [ -f "./SAxense/SAxense.c" ]; then
            (gcc -O3 ./SAxense/SAxense.c -o ./SAxense/SAxense > /dev/null 2>&1) & spinner $!
            BIN_PATH="./SAxense/SAxense"
        elif [ -f "./SAxense.c" ]; then
            (gcc -O3 ./SAxense.c -o ./SAxense > /dev/null 2>&1) & spinner $!
            BIN_PATH="./SAxense"
        else
            print_error "Could not find SAxense.c to build!"
            exit 1
        fi
    fi

    # Финальная страховка
    if [ ! -f "$BIN_PATH" ] ||[ -d "$BIN_PATH" ]; then
        print_error "Executable not found or is a directory!"
        exit 1
    fi
    
    chmod +x "$BIN_PATH"
    print_success "SAxense binary is ready ($BIN_PATH)."
}

# --- Task 3: Smart Device Discovery ---
discover_device() {
    print_info "🎮 Scanning for DualSense controller..."
    
    # 1. Primary method: Bluetooth (uhid) path used by original SAxense
    for path in /sys/devices/virtual/misc/uhid/*054C:0CE6*/hidraw/hidraw* \
                /sys/devices/virtual/misc/uhid/*054C:0DF2*/hidraw/hidraw*; do
        if [ -e "$path" ]; then
            DS_DEV="/dev/$(basename "$path")"
            break
        fi
    done

    # 2. Fallback method: USB or native kernel Bluetooth (standard hidraw class)
    if [ -z "$DS_DEV" ]; then
        for dev_path in /sys/class/hidraw/hidraw*; do
            if [ -f "$dev_path/device/uevent" ]; then
                if grep -iqE "HID_ID=.*:054C:(0CE6|0DF2)" "$dev_path/device/uevent" 2>/dev/null; then
                    DS_DEV="/dev/$(basename "$dev_path")"
                    break
                fi
            fi
        done
    fi

    if [ -z "$DS_DEV" ]; then
        print_error "DualSense controller not found!"
        print_info "Please ensure it is connected via Bluetooth or USB."
        exit 1
    fi
    print_success "Found DualSense at $DS_DEV"
}

# --- Task 4: Auto-Permissions (The "Fixer") ---
check_permissions() {
    if [ ! -w "$DS_DEV" ]; then
        print_warn "Write access to $DS_DEV denied."
        print_info "Installing universal udev rules via pkexec to grant access..."
        
        local RULE_FILE="/tmp/99-zensense-haptics.rules"
        cat << 'EOF' > "$RULE_FILE"
# ZenSense DualSense Haptics Access
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", TAG+="uaccess"
EOF
        # Apply safely through polkit
        if ! pkexec bash -c "cp $RULE_FILE /etc/udev/rules.d/ && udevadm control --reload-rules && udevadm trigger"; then
            print_error "Polkit execution failed or was canceled."
            exit 1
        fi

        sleep 2 # Wait for udev daemon to apply the trigger
        
        if [ ! -w "$DS_DEV" ]; then
            print_error "Still unable to write to $DS_DEV. Please replug the controller and restart."
            exit 1
        fi
        print_success "Permissions successfully applied."
    else
        print_success "Permissions look good."
    fi
}

# --- Task 5: Ask for Effects ---
prompt_effects() {
    echo ""
    print_prompt "Do you want to apply recommended haptic effects? [Y/n] "
    echo ""
    print_info "   (Applies a 250Hz Low-Pass Filter and slight Bass Boost)"
    print_info "   (Removes high-pitch buzzing, giving deep, clean haptics)"
    
    read -r -p "   Answer: " response
    if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
        USE_EFFECTS=false
        print_info "Effects disabled. Using raw audio stream."
    else
        USE_EFFECTS=true
        print_success "Effects enabled! (Low-Pass Filter + Boost)"
    fi
}

# --- Task 6: Audio Infrastructure ---
setup_audio() {
    print_info "🔊 Creating Virtual Audio Sink (DualSense_Haptics)..."
    
    # Unload just in case a leftover exists from a previous ungraceful exit
    pactl unload-module module-null-sink 2>/dev/null || true
    
    MODULE_ID=$(pactl load-module module-null-sink sink_name=DualSense_Haptics sink_properties=device.description="DualSense_Haptics")
    
    if [ -z "$MODULE_ID" ]; then
        print_error "Failed to create virtual audio sink via Pipewire/PulseAudio."
        exit 1
    fi
    print_success "Virtual sink created (ID: $MODULE_ID)."
}

# --- Task 7: Execution & Pipeline ---
run_pipeline() {
    echo -e "\n${C_CYAN}================================================================${C_RST}"
    print_success "All systems go! Routing audio to haptics."
    print_info "1. Open your Volume Mixer."
    print_info "2. Route your Game/Application audio to 'DualSense_Haptics'."
    print_info "Press ${C_RED}Ctrl+C${C_RST} ${C_BOLD}at any time to stop and clean up.${C_RST}"
    echo -e "${C_CYAN}================================================================${C_RST}\n"

    # Имя ноды для pw-record, чтобы авто-линкер точно знал, кого подключать
    local CAP_NODE="zensense_capture"

    # Авто-линкер (Абсолютная гарантия, что pw-record заберет звук из Haptics)
    (
        sleep 1.5
        # Подключаем мониторы раковины напрямую к рекордеру
        pw-link DualSense_Haptics:monitor_FL ${CAP_NODE}:input_FL 2>/dev/null || true
        pw-link DualSense_Haptics:monitor_FR ${CAP_NODE}:input_FR 2>/dev/null || true
        # Резерв на случай, если pw-record запустится в моно
        pw-link DualSense_Haptics:monitor_FL ${CAP_NODE}:input_MONO 2>/dev/null || true
    ) &

    # stream.capture.sink=true позволяет pw-record легально писать с выходов (Sinks)
    if [ "$USE_EFFECTS" = true ]; then
        stdbuf -o0 pw-record -P stream.capture.sink=true -P node.name="${CAP_NODE}" \
            --target=DualSense_Haptics --format=s8 --rate=3000 --channels=2 --latency=5ms - | \
        stdbuf -o0 sox --buffer 128 -V1 -t raw -r 3000 -e signed-integer -b 8 -c 2 - \
             -t raw -r 3000 -e signed-integer -b 8 -c 2 - lowpass 250 vol 1.3 | \
        stdbuf -i0 "$BIN_PATH" > "$DS_DEV"
    else
        stdbuf -o0 pw-record -P stream.capture.sink=true -P node.name="${CAP_NODE}" \
            --target=DualSense_Haptics --format=s8 --rate=3000 --channels=2 --latency=5ms - | \
        stdbuf -i0 "$BIN_PATH" > "$DS_DEV"
    fi
}

# --- Main Flow ---
main() {
    show_banner
    check_dependencies
    prepare_saxense
    discover_device
    check_permissions
    prompt_effects
    setup_audio
    run_pipeline
}

# Kickoff
main
