#!/usr/bin/env bash
#
# ==============================================================================
# ZenSense - Haptics Over Bluetooth (Pro Edition)
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
C_INV='\033[7m' # Invert for selections
C_BG_GREEN='\033[42;37m'

print_info()    { echo -e "${C_BLUE}ℹ ${C_RST} ${C_BOLD}$1${C_RST}"; }
print_success() { echo -e "${C_GREEN}✔ ${C_RST} ${C_BOLD}$1${C_RST}"; }
print_error()   { echo -e "${C_RED}✖ ${C_RST} ${C_BOLD}$1${C_RST}"; }
print_warn()    { echo -e "${C_YELLOW}⚠ ${C_RST} ${C_BOLD}$1${C_RST}"; }

# ASCII Banner
show_banner() {
    echo -e "${C_CYAN}"
    cat << "EOF"
  ______           _____
 |___  /          / ____|
    / / ___ _ __ | (___   ___ _ __  ___  ___
   / / / _ \ '_ \ \___ \ / _ \ '_ \/ __|/ _ \
  / /_|  __/ | | |____) |  __/ | | \__ \  __/
 /_____\___|_| |_|_____/ \___|_| |_|___/\___|

EOF
    echo -e "${C_RST}${C_BOLD}       DualSense Haptics Over Bluetooth       ${C_RST}"
    echo -e "${C_CYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RST}"
}

# --- Global State Variables ---
MODULE_ID=""
BIN_PATH=""
DS_DEV=""
SOX_FILTERS=""

# --- Cleanup Handler ---

cleanup() {
    trap - INT TERM EXIT # Отключаем повторный перехват сигналов, чтобы избежать двойного вывода
    tput cnorm # Always restore terminal cursor
    echo -e "\n\n"
    print_info "🧹 Shutting down ZenSense cleanly..."
    if [ -n "$MODULE_ID" ]; then
        pactl unload-module "$MODULE_ID" 2>/dev/null || true
        print_success "Virtual sink (DualSense_Haptics) removed."
    fi
    print_success "Goodbye!"
    exit 0
}
trap cleanup INT TERM EXIT

# --- Smooth Spinner Function ---
run_task() {
    local msg="$1"
    shift

    # Run the command in the background
    "$@" >/dev/null 2>&1 &
    local pid=$!
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    tput civis # Hide cursor
    while kill -0 "$pid" 2>/dev/null; do
        for (( i=0; i<${#spinstr}; i++ )); do
            printf "\r  ${C_CYAN}%s${C_RST} ${C_BOLD}%s...${C_RST}" "${spinstr:$i:1}" "$msg"
            sleep 0.1
            kill -0 "$pid" 2>/dev/null || break
        done
    done
    wait "$pid"
    local ret=$?

    printf "\r\033[K" # Clear the spinner line
    tput cnorm        # Show cursor

    if [ $ret -ne 0 ]; then
        print_error "$msg - FAILED!"
        exit 1
    fi
    print_success "$msg - Done"
}

# --- Task 1: Check Dependencies ---
check_dependencies() {
    local MISSING_CMDS=()
    for cmd in git gcc make pw-record pactl stdbuf sox grep sed pkexec pw-link; do
        if ! command -v "$cmd" &> /dev/null; then
            MISSING_CMDS+=("$cmd")
        fi
    done

    if [ ${#MISSING_CMDS[@]} -ne 0 ]; then
        print_warn "Missing required commands: ${MISSING_CMDS[*]}"
        print_info "Detecting Package Manager (You might be asked for password)..."

        if command -v pacman &> /dev/null; then
            sudo pacman -S --needed base-devel pipewire libpulse coreutils sox git polkit grep sed
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y build-essential pipewire pulseaudio-utils coreutils sox libsox-fmt-all git policykit-1
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y gcc make pipewire pulseaudio-utils coreutils sox git polkit
        else
            print_error "Unsupported OS. Please install missing packages manually: ${MISSING_CMDS[*]}"
            exit 1
        fi
        print_success "Dependencies resolved."
    fi
}

# --- Task 2: SAxense Build ---
prepare_saxense() {
    if [ ! -d "SAxense" ] && [ ! -f "SAxense.c" ]; then
        run_task "Cloning SAxense repository" git clone https://github.com/egormanga/SAxense.git ./SAxense
    fi

    if [ -f "./SAxense/SAxense" ] && [ ! -d "./SAxense/SAxense" ]; then
        BIN_PATH="./SAxense/SAxense"
    elif [ -f "./SAxense" ] &&[ ! -d "./SAxense" ]; then
        BIN_PATH="./SAxense"
    fi

    if [ -z "$BIN_PATH" ]; then
        if [ -f "./SAxense/Makefile" ]; then
            run_task "Building SAxense from source" make -C SAxense
            BIN_PATH="./SAxense/SAxense"
        elif [ -f "./SAxense/SAxense.c" ]; then
            run_task "Compiling SAxense core" gcc -O3 ./SAxense/SAxense.c -o ./SAxense/SAxense
            BIN_PATH="./SAxense/SAxense"
        fi
    fi
    chmod +x "$BIN_PATH"
}

# --- Task 3: Device Discovery ---
discover_device() {
    # Fake a slight delay to show the beautiful spinner
    run_task "Scanning Bluetooth & USB interfaces" sleep 1.5

    for path in /sys/devices/virtual/misc/uhid/*054C:0CE6*/hidraw/hidraw* /sys/devices/virtual/misc/uhid/*054C:0DF2*/hidraw/hidraw*; do
        if [ -e "$path" ]; then DS_DEV="/dev/$(basename "$path")"; break; fi
    done
    if [ -z "$DS_DEV" ]; then
        for dev_path in /sys/class/hidraw/hidraw*; do
            if [ -f "$dev_path/device/uevent" ] && grep -iqE "HID_ID=.*:054C:(0CE6|0DF2)" "$dev_path/device/uevent" 2>/dev/null; then
                DS_DEV="/dev/$(basename "$dev_path")"; break
            fi
        done
    fi
    if [ -z "$DS_DEV" ]; then print_error "DualSense not found! Please connect it."; exit 1; fi
    print_success "Found DualSense at $DS_DEV"
}

# --- Task 4: Permissions ---
check_permissions() {
    if [ ! -w "$DS_DEV" ]; then
        print_warn "Write access to $DS_DEV denied. Requesting fix via pkexec..."
        local RULE_FILE="/tmp/99-zensense-haptics.rules"
        cat << 'EOF' > "$RULE_FILE"
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", TAG+="uaccess"
EOF
        if ! pkexec bash -c "cp $RULE_FILE /etc/udev/rules.d/ && udevadm control --reload-rules && udevadm trigger"; then exit 1; fi
        sleep 2
    fi
}

# ==============================================================================
# INTERACTIVE TUI COMPONENTS
# ==============================================================================

# --- Custom Filter Builder Menu ---
custom_profile_menu() {
    local cursor=0
    local f_gate=1
    local f_highpass=1
    local f_bass=1
    local f_lowpass=1
    local f_over=0
    local f_vol=100

    draw_cb() {
        local idx=$1; local text=$2; local val=$3
        local prefix="    "

        if [ "$cursor" -eq "$idx" ]; then
            prefix="  ${C_CYAN}➜${C_RST} "
        fi

        local box="${C_RED}[ ]${C_RST}"
        if [ "$val" -eq 1 ]; then
            box="${C_GREEN}[✔]${C_RST}"
        fi

        if [ "$cursor" -eq "$idx" ]; then
            echo -e "${prefix}${C_BOLD}${text}${C_RST} ${box}"
        else
            echo -e "${prefix}${text} ${box}"
        fi
    }

    while true; do
        clear
        show_banner
        echo -e "   ${C_MAGENTA}⚙ CUSTOM PROFILE BUILDER${C_RST}"
        echo -e "   Use ${C_CYAN}UP/DOWN${C_RST} to move, ${C_CYAN}SPACE${C_RST} to toggle"
        echo -e "   Use ${C_CYAN}LEFT/RIGHT${C_RST} for slider, ${C_GREEN}ENTER${C_RST} to Apply\n"

        draw_cb 0 "Noise Gate       (Mute background noise)  " "$f_gate"
        draw_cb 1 "Subsonic Filter  (Tighten deep kicks)     " "$f_highpass"
        draw_cb 2 "Bass Boost       (Stronger gunshots/punch)" "$f_bass"
        draw_cb 3 "Low-Pass Filter  (Remove high-pitch whine)" "$f_lowpass"
        draw_cb 4 "Overdrive        (Gritty mechanical feel) " "$f_over"

        # Volume Slider Draw
        local v_prefix="    "
        if [ "$cursor" -eq 5 ]; then
            v_prefix="  ${C_CYAN}➜${C_RST} "
        fi

        local filled=$((f_vol / 10))
        local empty=$((25 - filled))
        local slider="["
        for ((i=0; i<filled; i++)); do slider+="█"; done
        for ((i=0; i<empty; i++)); do slider+="░"; done
        slider+="]"

        if [ "$cursor" -eq 5 ]; then
            echo -e "\n${v_prefix}${C_BOLD}Global Intensity:${C_RST} ${C_YELLOW}${slider} ${f_vol}%${C_RST}"
        else
            echo -e "\n${v_prefix}Global Intensity: ${slider} ${f_vol}%"
        fi

        # Apply Button Draw
        local b_prefix="    "
        local b_style="${C_BOLD}"
        if [ "$cursor" -eq 6 ]; then
            b_prefix="  ${C_CYAN}➜${C_RST} "
            b_style="${C_BG_GREEN}${C_BOLD} "
        fi
        echo -e "\n${b_prefix}${b_style}[  APPLY & START  ]${C_RST}"

        # Hint text
        echo -e "\n   ${C_BLUE}ℹ Hint:${C_RST}"
        case "$cursor" in
            0) echo -e "     Activates haptics only on loud sounds. Prevents constant rumble." ;;
            1) echo -e "     Cuts below 30Hz to save battery and stop motors from 'choking'." ;;
            2) echo -e "     Amplifies the 75Hz range where the DualSense resonates best." ;;
            3) echo -e "     Cuts off voices/music so the controller doesn't buzz like a speaker." ;;
            4) echo -e "     Adds soft clipping for a raw, heavy sensation (great for mech/cars)." ;;
            5) echo -e "     Increase or decrease the overall strength of all haptic forces." ;;
            6) echo -e "     Save this profile and launch ZenSense." ;;
        esac

        # Исправлено чтение клавиш (добавлен IFS=)
        IFS= read -rsn1 key
        if [[ $key == $'\e' ]]; then
            read -rsn2 k2
            key+="$k2"
        fi

        case "$key" in
            $'\e[A') # UP
                cursor=$((cursor - 1))
                [ "$cursor" -lt 0 ] && cursor=6
                ;;
            $'\e[B') # DOWN
                cursor=$((cursor + 1))
                [ "$cursor" -gt 6 ] && cursor=0
                ;;
            $'\e[C') # RIGHT
                if [ "$cursor" -eq 5 ] &&[ "$f_vol" -lt 250 ]; then
                    f_vol=$((f_vol + 10))
                fi
                ;;
            $'\e[D') # LEFT
                if [ "$cursor" -eq 5 ] && [ "$f_vol" -gt 10 ]; then
                    f_vol=$((f_vol - 10))
                fi
                ;;
            ' ') # SPACE
                case "$cursor" in
                    0) f_gate=$((1 - f_gate)) ;;
                    1) f_highpass=$((1 - f_highpass)) ;;
                    2) f_bass=$((1 - f_bass)) ;;
                    3) f_lowpass=$((1 - f_lowpass)) ;;
                    4) f_over=$((1 - f_over)) ;;
                esac
                ;;
            '') # ENTER
                break ;;
        esac
    done

    # Исправлен баг, из-за которого склеивались строки SOX
    SOX_FILTERS=""[ "$f_highpass" -eq 1 ] && SOX_FILTERS+="highpass 30 "[ "$f_gate" -eq 1 ]     && SOX_FILTERS+="compand 0.05,0.1 -inf,-35,-inf,-30,-30,0,0 "[ "$f_over" -eq 1 ]     && SOX_FILTERS+="overdrive 5 "
    [ "$f_bass" -eq 1 ]     && SOX_FILTERS+="bass +8 75 "
    [ "$f_lowpass" -eq 1 ]  && SOX_FILTERS+="lowpass 250 "

    # Calculate volume float (e.g., 100 -> 1.0)
    local v_int=$((f_vol / 100))
    local v_dec=$(( (f_vol % 100) / 10 ))
    SOX_FILTERS+="vol ${v_int}.${v_dec}"

    clear
    show_banner
    print_success "Custom Profile Applied!"
}
# --- Main Profile Selection Menu ---
prompt_profile() {
    tput civis # Hide terminal cursor
    local selected=2
    local options=(
        "Basic  (Original Setting: Low-pass only)"
        "None   (Raw Game Audio - No Filters)"
        "Custom (Interactive Filter & Power Builder)"
    )

    while true; do
        clear
        show_banner
        echo -e "   ${C_MAGENTA}⚙ Select Haptics Profile:${C_RST}\n"

        for i in "${!options[@]}"; do
            if [ "$i" -eq "$selected" ]; then
                echo -e "   ${C_CYAN}➜${C_RST} ${C_INV} ${options[$i]} ${C_RST}"
            else
                echo -e "      ${options[$i]} "
            fi
        done

        echo -e "\n   (Use ${C_CYAN}UP/DOWN${C_RST} to select, ${C_GREEN}ENTER${C_RST} to confirm)"

        # Исправлено чтение клавиш (добавлен IFS=)
        IFS= read -rsn1 key
        if [[ $key == $'\e' ]]; then
            read -rsn2 k2
            key+="$k2"
        fi

        case "$key" in
            $'\e[A')
                selected=$((selected - 1))[ "$selected" -lt 0 ] && selected=2
                ;;
            $'\e[B')
                selected=$((selected + 1))
                [ "$selected" -gt 2 ] && selected=0
                ;;
            '') break ;;
        esac
    done
    tput cnorm # Show terminal cursor

    # Process selection
    case "$selected" in
        0)
            SOX_FILTERS="lowpass 250 vol 1.3"
            clear; show_banner
            print_success "Basic Profile Applied!"
            ;;
        1)
            SOX_FILTERS=""
            clear; show_banner
            print_warn "Filters disabled. Using raw audio."
            ;;
        2)
            tput civis
            custom_profile_menu
            tput cnorm
            ;;
    esac
}

# --- Task 6: Audio Routing Setup ---
setup_audio() {
    run_task "Creating Virtual Audio Sink" sleep 1.0 # Aesthetics
    pactl unload-module module-null-sink 2>/dev/null || true
    MODULE_ID=$(pactl load-module module-null-sink sink_name=DualSense_Haptics sink_properties=device.description="DualSense_Haptics")
    if [ -z "$MODULE_ID" ]; then print_error "Failed to create audio sink."; exit 1; fi
}

# --- Task 7: Execute SoX Pipeline ---
run_pipeline() {
    echo -e "\n${C_CYAN}================================================================${C_RST}"
    print_success "All systems go! Routing audio to haptics."
    print_info "1. Open your Volume Mixer."
    print_info "2. Route Game/Application audio to 'DualSense_Haptics'."
    print_info "Press ${C_RED}Ctrl+C${C_RST} ${C_BOLD}at any time to stop and clean up.${C_RST}"
    echo -e "${C_CYAN}================================================================${C_RST}\n"

    local CAP_NODE="zensense_capture"

    # Auto-Linker
    (
        sleep 1.5
        pw-link DualSense_Haptics:monitor_FL ${CAP_NODE}:input_FL 2>/dev/null || true
        pw-link DualSense_Haptics:monitor_FR ${CAP_NODE}:input_FR 2>/dev/null || true
        pw-link DualSense_Haptics:monitor_FL ${CAP_NODE}:input_MONO 2>/dev/null || true
    ) &

    # Launch Pipeline
    if [ -n "$SOX_FILTERS" ]; then
        # $SOX_FILTERS unquoted here allows bash to word-split the parameters directly into sox
        stdbuf -o0 pw-record -P stream.capture.sink=true -P node.name="${CAP_NODE}" \
            --target=DualSense_Haptics --format=s8 --rate=3000 --channels=2 --latency=5ms - | \
        stdbuf -o0 sox --buffer 128 -V1 -t raw -r 3000 -e signed-integer -b 8 -c 2 - \
             -t raw -r 3000 -e signed-integer -b 8 -c 2 - $SOX_FILTERS | \
        stdbuf -i0 "$BIN_PATH" > "$DS_DEV"
    else
        stdbuf -o0 pw-record -P stream.capture.sink=true -P node.name="${CAP_NODE}" \
            --target=DualSense_Haptics --format=s8 --rate=3000 --channels=2 --latency=5ms - | \
        stdbuf -i0 "$BIN_PATH" > "$DS_DEV"
    fi
}

# --- Main Flow ---
main() {
    clear
    show_banner
    check_dependencies
    echo ""
    prepare_saxense
    discover_device
    check_permissions
    sleep 1

    # Run the interactive TUI
    prompt_profile

    setup_audio
    run_pipeline
}

main
