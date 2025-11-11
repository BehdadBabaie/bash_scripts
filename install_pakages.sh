#!/bin/bash
# ---------------------------------------
# Arch Linux Package Auto Installer
# ---------------------------------------
# Installs core utilities and updates system automatically.

set -e  # Exit immediately if a command fails

# ===== List of official repo packages =====
PACKAGES=(
    # lemurs
    ly
    alacritty
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
)

# ===== Optional: AUR packages (will use yay if installed) =====
AUR_PACKAGES=(
    brave-bin
    blesh-git
)

echo "======================================="
echo " Arch Linux Package Installation Script"
echo "======================================="

# ===== Update system and install main packages =====
echo "==> Updating system and installing core packages..."
sudo pacman -Syu --noconfirm "${PACKAGES[@]}"

# ===== Check and install AUR packages if yay is available =====
if command -v yay &>/dev/null; then
    echo "==> yay found, installing AUR packages..."
    yay -S --noconfirm "${AUR_PACKAGES[@]}"
else
    echo "⚠️  yay not found, skipping AUR packages."
fi

# ===== Update tldr cache =====
if command -v tldr &>/dev/null; then
    echo "==> Updating TLDR cache..."
    tldr --update
fi

echo "======================================="
echo "✅ All installations completed successfully!"
echo "======================================="
