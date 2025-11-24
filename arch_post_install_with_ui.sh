#!/bin/bash
# ---------------------------------------------------------
# Arch Linux Post-Install Script
# ---------------------------------------------------------

set -euo pipefail

# =======================
# Colors
# =======================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# =======================
# Dotfiles repo
# =======================
DOTFILES_REPO="https://github.com/BehdadBabaie/dotfiles.git"
DOTFILES_DIR="$HOME/.dotfiles"

# =======================
# Package lists
# =======================
PACKAGES=(
    base-devel git stow alacritty neovim starship curl wget unzip htop man-db tldr
    fastfetch eza xorg xdg-user-dirs bash-completion brightnessctl pamixer lm_sensors ly
)

AUR_PACKAGES=(
    brave-bin blesh-git
)

# =======================
# Detect VM
# =======================
if systemd-detect-virt --quiet; then
    PACKAGES+=(virtualbox-guest-utils)
fi

# =======================
# Pretty header
# =======================
echo -e "${YELLOW}=======================================${NC}"
echo -e "${GREEN}  Arch Post-Install Script Running...  ${NC}"
echo -e "${YELLOW}=======================================${NC}"

# =======================
# Update system
# =======================
echo -e "${GREEN}==> Updating system...${NC}"
sudo pacman -Syu --noconfirm

# =======================
# Install official pkgs
# =======================
echo -e "${GREEN}==> Installing official packages...${NC}"
sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"

# =======================
# Install yay
# =======================
if ! command -v yay &>/dev/null; then
    echo -e "${GREEN}==> Installing yay...${NC}"
    sudo pacman -S --needed --noconfirm git base-devel

    TMPDIR=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$TMPDIR/yay"
    (cd "$TMPDIR/yay" && makepkg -si --noconfirm)

    rm -rf "$TMPDIR"
    cd "$HOME"   # <<< FIX: return to safe directory
else
    echo -e "${YELLOW}Yay already installed.${NC}"
fi

# =======================
# Install AUR pkgs
# =======================
echo -e "${GREEN}==> Installing AUR packages...${NC}"
yay -S --needed --noconfirm "${AUR_PACKAGES[@]}"

# =======================
# Clone dotfiles
# =======================
echo -e "${GREEN}==> Cloning dotfiles...${NC}"
if [[ ! -d "$DOTFILES_DIR" ]]; then
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
    echo -e "${YELLOW}Dotfiles directory already exists.${NC}"
fi

# =======================
# STOW modules
# =======================
echo -e "${GREEN}==> Stowing modules...${NC}"
cd "$DOTFILES_DIR"

for module in */; do
    module="${module%/}"
    [[ -d "$module" ]] || continue
    echo -e "${GREEN}Stowing: $module${NC}"
    stow "$module"
done

# =======================
# Update font cache
# =======================
if [[ -d "fonts/.local/share/fonts" ]]; then
    fc-cache -fv
fi

# =======================
# Build suckless WMs
# =======================
for app in dwm dmenu dwmblocks-async; do
    if [[ -d "$DOTFILES_DIR/$app" ]]; then
        echo -e "${GREEN}==> Building $app...${NC}"
        (cd "$DOTFILES_DIR/$app" && sudo make clean install)
    fi
done

# =======================
# Install .desktop files
# =======================
echo -e "${GREEN}==> Installing .desktop session files...${NC}"

if [[ ! -d /usr/share/xsessions ]]; then
    echo -e "${YELLOW}/usr/share/xsessions missing — creating it.${NC}"
    sudo mkdir -p /usr/share/xsessions
fi

if [[ -d "$DOTFILES_DIR/desktop" ]]; then
    for file in "$DOTFILES_DIR"/desktop/*.desktop; do
        [[ -f "$file" ]] || continue
        sudo install -m 644 "$file" /usr/share/xsessions/
    done
fi

# =======================
# Interactive WM selection
# =======================
echo -e "${GREEN}==> Available window managers detected:${NC}"

WMS=()
[[ -d "$DOTFILES_DIR/dwm" ]] && WMS+=("dwm")
[[ -d "$DOTFILES_DIR/i3" ]] && WMS+=("i3")
[[ -d "$DOTFILES_DIR/openbox" ]] && WMS+=("openbox")

select wm in "${WMS[@]}"; do
    [[ -n "$wm" ]] && break
done

echo -e "${GREEN}Selected WM: $wm${NC}"

# =======================
# Interactive DM selection
# =======================
echo -e "${GREEN}==> Choose a Display Manager:${NC}"
PS3="Select DM: "

select dm in "ly" "lemurs"; do
    [[ -n "$dm" ]] && break
done

echo -e "${GREEN}Selected DM: $dm${NC}"

sudo systemctl disable --now ly.service 2>/dev/null || true
sudo systemctl disable --now lemurs.service 2>/dev/null || true
sudo systemctl enable --now "$dm".service

# =======================
# Final touches
# =======================
tldr --update || true
xdg-user-dirs-update || true

echo -e "${YELLOW}=======================================${NC}"
echo -e "${GREEN}   ✓ Full system setup complete!   ${NC}"
echo -e "${YELLOW}=======================================${NC}"
