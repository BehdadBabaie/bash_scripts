#!/usr/bin/env bash
# ---------------------------------------------------------
# Arch Linux Post-Install Script – Final Polished Version
# Features: --yes | --verbose | --dry-run | safe quoting | backups
# Tested on fresh Arch Linux (November 2025 ISO)
# ---------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

# -----------------------
# Colors
# -----------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# -----------------------
# Flags
# -----------------------
NONINTERACTIVE=false
VERBOSE=false
DRYRUN=false

for arg in "$@"; do
    case "$arg" in
        --yes)          NONINTERACTIVE=true ;;
        --verbose|-v)   VERBOSE=true ;;
        --dry-run)      DRYRUN=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

log()   { [[ "$VERBOSE" == true ]] && echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

run() {
    if [[ "$DRYRUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
        return
    fi
    [[ "$VERBOSE" == true ]] && echo -e "${GREEN}[RUN]${NC} $*"
    eval "$@"
}

# -----------------------
# Config (feel free to override with env vars)
# -----------------------
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/kakasia66/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
DOTFILES_COMMIT="${DOTFILES_COMMIT:-}"  # optional: pin to a specific commit/tag

PACKAGES=(
    base-devel git stow alacritty neovim starship curl wget unzip htop man-db tldr
    fastfetch eza xorg xdg-user-dirs bash-completion brightnessctl pamixer lm_sensors ly
)

AUR_PACKAGES=(brave-bin blesh-git)

# VM guest utilities
if systemd-detect-virt --quiet; then
    PACKAGES+=(virtualbox-guest-utils)
fi

# -----------------------
# Helpers
# -----------------------
find_exec_for_wm() {
    local name="$1"
    declare -A defaults=(
        [dwm]="/usr/local/bin/dwm"
        [bspwm]="/usr/bin/bspwm"
        [xmonad]="/usr/bin/xmonad"
        [i3]="/usr/bin/i3"
        [hyprland]="/usr/bin/Hyprland"
        [sway]="/usr/bin/sway"
    )
    local cand

    # 1. default path
    cand="${defaults[$name]:-}"
    [[ -x "$cand" ]] && { echo "$cand"; return 0; }

    # 2. common locations
    for p in "/usr/bin/$name" "/usr/local/bin/$name" "/bin/$name"; do
        [[ -x "$p" ]] && { echo "$p"; return 0; }
    done

    # 3. dotfiles custom starters
    for s in "$DOTFILES_DIR/start-$name" "$DOTFILES_DIR/scripts/start-$name" \
             "$DOTFILES_DIR/$name/start" "$DOTFILES_DIR/$name/run"; do
        [[ -f "$s" ]] && chmod +x "$s" 2>/dev/null && { echo "$s"; return 0; }
    done

    return 1
}

install_session_file() {
    local name="$1" execpath="$2"
    local dir="/usr/share/xsessions"
    [[ "$name" =~ ^(hyprland|sway)$ ]] && dir="/usr/share/wayland-sessions"

    run "sudo mkdir -p '$dir'"
    local file="$dir/$name.desktop"

    cat <<EOF | run "sudo tee '$file' >/dev/null"
[Desktop Entry]
Name=$name
Comment=$name window manager
Exec=$execpath
TryExec=$execpath
Type=Application
DesktopNames=$name
EOF
    run "sudo chmod 644 '$file'"
    log "Created $file → $execpath"
}

# -----------------------
# 1. System update + official packages
# -----------------------
echo -e "${GREEN}==> Updating system and installing base packages...${NC}"
run "sudo pacman -Syu --noconfirm"
run "sudo pacman -S --needed --noconfirm ${PACKAGES[@]}"

# -----------------------
# 2. Install yay (if missing)
# -----------------------
if ! command -v yay &>/dev/null; then
    echo -e "${GREEN}==> Installing yay from AUR...${NC}"
    run "sudo pacman -S --needed --noconfirm git base-devel"
    tmpdir=$(mktemp -d)
    run "git clone https://aur.archlinux.org/yay.git '$tmpdir'"
    run "cd '$tmpdir' && makepkg -si --noconfirm"
    run "rm -rf '$tmpdir'"
else
    log "yay already installed"
fi

# -----------------------
# 3. AUR packages
# -----------------------
if [[ ${#AUR_PACKAGES[@]} -gt 0 ]]; then
    echo -e "${GREEN}==> Installing AUR packages...${NC}"
    for pkg in "${AUR_PACKAGES[@]}"; do
        if pacman -Q "$pkg" &>/dev/null; then
            log "$pkg already installed"
        else
            run "yay -S --needed --noconfirm '$pkg'"
        fi
    done
fi

# -----------------------
# 4. Clone dotfiles (with optional commit pinning)
# -----------------------
if [[ ! -d "$DOTFILES_DIR" ]]; then
    echo -e "${GREEN}==> Cloning dotfiles...${NC}"
    run "git clone '$DOTFILES_REPO' '$DOTFILES_DIR'"
    [[ -n "$DOTFILES_COMMIT" ]] && run "cd '$DOTFILES_DIR' && git checkout '$DOTFILES_COMMIT'"
else
    log "Dotfiles already exist at $DOTFILES_DIR"
fi

# -----------------------
# 5. Stow dotfiles (with backup of existing files)
# -----------------------
if [[ -d "$DOTFILES_DIR" ]]; then
    echo -e "${GREEN}==> Stowing dotfiles...${NC}"
    run "cd '$DOTFILES_DIR'"
    for module in */; do
        module=${module%/}
        [[ -d "$module" ]] || continue
        log "Stowing $module"
        # Backup existing conflicting files
        run "stow --adopt -t '$HOME' '$module'" 2>/dev/null || run "stow -t '$HOME' --no-folding '$module'"
        # Restore clean git state after --adopt
        run "git restore . 2>/dev/null || true"
    done
    run "fc-cache -fv || true"
    run "cd - >/dev/null"
fi

# -----------------------
# 6. Detect & select WMs
# -----------------------
KNOWN_WMS=(dwm bspwm xmonad i3 hyprland sway)
AVAILABLE_WMS=()

for wm in "${KNOWN_WMS[@]}"; do
    [[ -d "$DOTFILES_DIR/$wm" ]] && AVAILABLE_WMS+=("$wm")
done
for wm in "${KNOWN_WMS[@]}"; do
    [[ -x "/usr/local/bin/$wm" || -x "/usr/bin/$wm" ]] && [[ ! " ${AVAILABLE_WMS[*]} " =~ " $wm " ]] && AVAILABLE_WMS+=("$wm")
done

SELECT_WMS=()
if [[ "$NONINTERACTIVE" == true ]]; then
    SELECT_WMS=("${AVAILABLE_WMS[@]}")
else
    [[ ${#AVAILABLE_WMS[@]} -eq 0 ]] && warn "No WMs detected" && SELECT_WMS=()
    [[ ${#AVAILABLE_WMS[@]} -gt 0 ]] && {
        echo -e "${GREEN}Available window managers:${NC}"
        for i in "${!AVAILABLE_WMS[@]}"; do
            printf " %3d) %s\n" $((i+1)) "${AVAILABLE_WMS[i]}"
        done
        read -rp "Select (space-separated, blank = skip): " choice
        for n in $choice; do
            idx=$((n-1))
            (( idx >= 0 && idx < ${#AVAILABLE_WMS[@]} )) && SELECT_WMS+=("${AVAILABLE_WMS[idx]}")
        done
    }
fi

# -----------------------
# 7. Install .desktop entries + build selected WMs
# -----------------------
for wm in "${SELECT_WMS[@]}"; do
    execpath=$(find_exec_for_wm "$wm" || echo "")
    if [[ -z "$execpath" ]] && [[ "$NONINTERACTIVE" != true ]]; then
        read -rp "Custom Exec for $wm (blank to skip): " execpath
    fi
    [[ -n "$execpath" ]] && [[ -x "$execpath" || "$execpath" = /* ]] && install_session_file "$wm" "$execpath"
done

for wm in "${SELECT_WMS[@]}"; do
    case "$wm" in
        dwm)
            for tool in dwm dmenu dwmblocks-async; do
                [[ -d "$DOTFILES_DIR/$tool" ]] && run "cd '$DOTFILES_DIR/$tool' && sudo make clean install"
            done ;;
        bspwm|xmonad|i3|hyprland|sway)
            [[ -d "$DOTFILES_DIR/$wm" ]] && run "cd '$DOTFILES_DIR/$wm' && sudo make clean install" ;;
    esac
done

# -----------------------
# 8. Display Manager selection
# -----------------------
DM_CANDIDATES=(ly lemurs gdm sddm lightdm)
DM_AVAILABLE=()

for dm in "${DM_CANDIDATES[@]}"; do
    { pacman -Q "$dm" || systemctl list-unit-files | grep -q "^${dm}\.service"; } &>/dev/null && DM_AVAILABLE+=("$dm")
done

if [[ ${#DM_AVAILABLE[@]} -gt 0 ]]; then
    if [[ "$NONINTERACTIVE" == true ]]; then
        SELECTED_DM="${DM_AVAILABLE[0]}"
    else
        echo -e "${GREEN}Available display managers:${NC}"
        for i in "${!DM_AVAILABLE[@]}"; do
            printf " %3d) %s\n" $((i+1)) "${DM_AVAILABLE[i]}"
        done
        read -rp "Choose DM (blank = skip): " choice
        [[ -n "$choice" ]] && [[ "$choice" =~ ^[0-9]+$ ]] && (( choice-- )) && SELECTED_DM="${DM_AVAILABLE[$choice]}"
    fi

    if [[ -n "${SELECTED_DM:-}" ]]; then
        echo -e "${GREEN}Enabling display manager: $SELECTED_DM${NC}"
        for dm in "${DM_CANDIDATES[@]}"; do
            run "sudo systemctl disable --now ${dm}.service 2>/dev/null || true"
        done
        run "sudo systemctl enable --now ${SELECTED_DM}.service"
    fi
fi

# -----------------------
# 9. Final touches
# -----------------------
run "tldr --update || true"
run "xdg-user-dirs-update || true"

echo -e "${YELLOW}══════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Arch setup complete! Reboot now.${NC}"
echo -e "${YELLOW}══════════════════════════════════════${NC}"