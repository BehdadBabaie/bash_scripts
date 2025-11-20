#!/bin/bash
# ---------------------------------------
# Arch Linux Package Auto Installer
# ---------------------------------------
set -euo pipefail  # Exit immediately if a command fails

# ===== Colors for pretty output (optional but nice) =====
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ===== Packages from official repos =====
PACKAGES=(
    ly
    alacritty
    bash-completion
    linux-headers
    base-devel
    dkms
    virtualbox-guest-utils
    bat
    man-db
    tldr
    git
    curl
    htop
    unzip
    wget
    xdg-user-dirs
    stow
    nvim
    starship
    fzf
    fastfetch
    eza
    openssh
    xorg
    # ==== Fonts =====
    ttf-meslo-nerd
    ttf-firacode-nerd
    ttf-ubuntu-mono-nerd
    ttf-ubuntu-nerd
    # ==== dependencies for dwmblocks =====
    xcb-util 
    xcb-util-wm
    xcb-util-xrm
    lm_sensors
    brightnessctl
    pamixer
)

# ===== Remove duplicates automatically =====
mapfile -t PACKAGES < <(printf '%s\n' "${PACKAGES[@]}" | sort -u)

# ===== AUR packages =====
AUR_PACKAGES=(
    brave-bin
    blesh-git
)

echo -e "${YELLOW}=======================================${NC}"
echo -e "${YELLOW}   Arch Linux Post-Install Script${NC}"
echo -e "${YELLOW}=======================================${NC}"

# ===== Update + install official packages (split to avoid set -e death) =====
echo -e "${GREEN}==> Updating system...${NC}"
sudo pacman -Sy --noconfirm

echo -e "${GREEN}==> Installing core packages...${NC}"
sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"

# ===== Install yay if missing =====
if ! command -v yay &>/dev/null; then
    echo -e "${GREEN}==> Installing yay from AUR...${NC}"
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd /
    rm -rf /tmp/yay
    echo -e "${GREEN}✅ yay installed!${NC}"
else
    echo -e "${GREEN}==> yay already installed${NC}"
fi

# ===== Install AUR packages =====
echo -e "${GREEN}==> Installing AUR packages...${NC}"
yay -S --noconfirm "${AUR_PACKAGES[@]}"

# ===== Final touches =====
if command -v tldr &>/dev/null; then
    echo -e "${GREEN}==> Updating tldr cache...${NC}"
    tldr --update
fi

# ===== Enable some useful services for VirtualBox / guest ======
if systemctl is-enabled vboxservice &>/dev/null || [ -x /usr/bin/VBoxService ]; then
    echo -e "${GREEN}==> Enabling VirtualBox guest services...${NC}"
    sudo systemctl enable --now vboxservice
fi

echo -e "${YELLOW}=======================================${NC}"
echo -e "${GREEN}✅ All done! Your system is ready.${NC}"
echo -e "${YELLOW}=======================================${NC}"