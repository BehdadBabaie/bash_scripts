#!/usr/bin/env bash
# ---------------------------------------------------------
# Arch Linux Post-Install Script (Interactive + Non-Interactive + Verbose + Dry-run)
# Features:
# - Package installation (official + AUR)
# - Clone dotfiles, stow modules, fonts, wallpapers
# - Build WMs/tools selectively
# - Interactive or --yes non-interactive mode
# - Verbose and dry-run options
# ---------------------------------------------------------

set -euo pipefail

# -----------------------
# Colors
# -----------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# -----------------------
# Script flags
# -----------------------
NONINTERACTIVE=false
VERBOSE=false
DRYRUN=false

for arg in "$@"; do
    case "$arg" in
        --yes) NONINTERACTIVE=true ;;
        --verbose) VERBOSE=true ;;
        --dry-run) DRYRUN=true ;;
    esac
done

log() { [[ "$VERBOSE" == true ]] && echo -e "$1"; }
run() { [[ "$DRYRUN" == true ]] && echo "[DRY-RUN] $*" || bash -c "$*"; }

# -----------------------
# Config
# -----------------------
DOTFILES_REPO="https://github.com/kakasia66/dotfiles.git"
DOTFILES_DIR="$HOME/.dotfiles"

PACKAGES=(
  base-devel git stow alacritty neovim starship curl wget unzip htop man-db tldr
  fastfetch eza xorg xdg-user-dirs bash-completion brightnessctl pamixer lm_sensors ly
)
AUR_PACKAGES=(brave-bin blesh-git)

# -----------------------
# VM detection
# -----------------------
if systemd-detect-virt --quiet; then
  PACKAGES+=(virtualbox-guest-utils)
fi

# -----------------------
# System update and package installation
# -----------------------
echo -e "${GREEN}==> Updating system...${NC}"
run "sudo pacman -Syu --noconfirm"

echo -e "${GREEN}==> Installing official packages...${NC}"
run "sudo pacman -S --needed --noconfirm ${PACKAGES[*]}"

# -----------------------
# Install yay (AUR helper)
# -----------------------
if ! command -v yay &>/dev/null; then
    echo -e "${GREEN}==> Installing yay...${NC}"
    run "sudo pacman -S --needed --noconfirm git base-devel"
    TMPDIR=$(mktemp -d)
    run "git clone https://aur.archlinux.org/yay.git '$TMPDIR/yay'"
    run "cd '$TMPDIR/yay' && makepkg -si --noconfirm"
    run "rm -rf '$TMPDIR'"
else
    log "yay already installed"
fi

# -----------------------
# Install AUR packages
# -----------------------
if [[ ${#AUR_PACKAGES[@]} -gt 0 ]]; then
  echo -e "${GREEN}==> Installing AUR packages...${NC}"
  any_aur_installed=false
  for pkg in "${AUR_PACKAGES[@]}"; do
      if ! pacman -Q "$pkg" &>/dev/null; then
          run "yay -S --needed --noconfirm $pkg"
          any_aur_installed=true
      else
          log "$pkg already installed, skipping"
      fi
  done
  if [[ "$any_aur_installed" == false ]]; then
      echo -e "${YELLOW}All AUR packages are already installed, nothing to do.${NC}"
  fi
fi

# -----------------------
# Clone dotfiles
# -----------------------
if [[ ! -d "$DOTFILES_DIR" ]]; then
  echo -e "${GREEN}==> Cloning dotfiles...${NC}"
  run "git clone '$DOTFILES_REPO' '$DOTFILES_DIR'"
else
  log "Dotfiles already present, skipping clone"
fi

# -----------------------
# Stow modules
# -----------------------
if [[ -d "$DOTFILES_DIR" ]]; then
  echo -e "${GREEN}==> Stowing modules...${NC}"
  pushd "$DOTFILES_DIR" >/dev/null
  for module in */; do
    module=${module%/}
    if [[ -d "$module" ]]; then
      log "Stowing $module"
      run "stow --target='$HOME' --no-folding '$module'" || true
    fi
  done
  if [[ -d "fonts/.local/share/fonts" || -d ".local/share/fonts" ]]; then
      log "Updating font cache"
      run "fc-cache -fv" || true
  fi
  popd >/dev/null
fi

# -----------------------
# Detect available WMs
# -----------------------
KNOWN_WMS=(dwm bspwm xmonad i3 hyprland sway)
AVAILABLE_WMS=()
for wm in "${KNOWN_WMS[@]}"; do
  [[ -d "$DOTFILES_DIR/$wm" ]] && AVAILABLE_WMS+=("$wm")
done

for wm in "${KNOWN_WMS[@]}"; do
  if [[ -x "/usr/bin/$wm" || -x "/usr/local/bin/$wm" ]]; then
    [[ ! " ${AVAILABLE_WMS[*]} " =~ " $wm " ]] && AVAILABLE_WMS+=("$wm")
  fi
done

# -----------------------
# Select WMs interactively or auto (--yes)
# -----------------------
SELECT_WMS=()
if [[ "$NONINTERACTIVE" == true ]]; then
  SELECT_WMS=("${AVAILABLE_WMS[@]}")
else
  if [[ ${#AVAILABLE_WMS[@]} -gt 0 ]]; then
    echo "Available WMs:"
    for idx in "${!AVAILABLE_WMS[@]}"; do printf " %d) %s\n" $((idx+1)) "${AVAILABLE_WMS[$idx]}"; done
    read -rp "Enter numbers separated by space (blank to skip): " sel
    for n in $sel; do
      i=$((n-1))
      (( i >= 0 && i < ${#AVAILABLE_WMS[@]} )) && SELECT_WMS+=("${AVAILABLE_WMS[$i]}")
    done
  fi
fi

# -----------------------
# Install .desktop files for selected WMs
# -----------------------
if [[ ${#SELECT_WMS[@]} -gt 0 ]]; then
  for wm in "${SELECT_WMS[@]}"; do
    execpath=""  # initialize variable to prevent unbound variable error
    execpath="$(find_exec_for_wm "$wm" 2>/dev/null || true)"
    if [[ -n "$execpath" ]]; then
      install_session_file "$wm" "$execpath"
    elif [[ "$NONINTERACTIVE" != true ]]; then
      read -rp "Enter custom Exec for $wm (blank to skip): " ce
      [[ -n "$ce" ]] && install_session_file "$wm" "$ce"
    else
      log "No executable found for $wm, skipping .desktop creation"
    fi
  done
fi

# -----------------------
# Build WMs/tools safely
# -----------------------
if [[ ${#SELECT_WMS[@]} -gt 0 ]]; then
  for wm in "${SELECT_WMS[@]}"; do
    case "$wm" in
      dwm)
        [[ -d "$DOTFILES_DIR/dwm" ]] && run "cd '$DOTFILES_DIR/dwm' && sudo make clean install"
        [[ -d "$DOTFILES_DIR/dmenu" ]] && run "cd '$DOTFILES_DIR/dmenu' && sudo make clean install"
        [[ -d "$DOTFILES_DIR/dwmblocks-async" ]] && run "cd '$DOTFILES_DIR/dwmblocks-async' && sudo make clean install"
        ;;
      bspwm|xmonad|i3|hyprland|sway)
        [[ -d "$DOTFILES_DIR/$wm" ]] && run "cd '$DOTFILES_DIR/$wm' && sudo make clean install"
        ;;
    esac
  done
fi

# -----------------------
# Detect and select DM
# -----------------------
DM_CANDIDATES=(ly lemurs gdm sddm lightdm)
DM_AVAILABLE=()
for dm in "${DM_CANDIDATES[@]}"; do
  pacman -Q "$dm" &>/dev/null || systemctl list-unit-files | grep -q "^${dm}\.service" && DM_AVAILABLE+=("$dm")
done

if [[ ${#DM_AVAILABLE[@]} -gt 0 ]]; then
  if [[ "$NONINTERACTIVE" == true ]]; then
    SELECTED_DM="${DM_AVAILABLE[0]}"
    echo -e "${GREEN}Enabling DM: $SELECTED_DM${NC}"
    for d in ly lemurs gdm sddm lightdm; do run "sudo systemctl disable --now '${d}.service' 2>/dev/null || true"; done
    run "sudo systemctl enable --now '${SELECTED_DM}.service'"
  else
    echo "Available DMs:"
    for idx in "${!DM_AVAILABLE[@]}"; do printf " %d) %s\n" $((idx+1)) "${DM_AVAILABLE[$idx]}"; done
    read -rp "Select DM number (blank to skip): " dm_sel
    if [[ -n "$dm_sel" ]]; then
      sel=$((dm_sel-1))
      (( sel >=0 && sel < ${#DM_AVAILABLE[@]} )) && SELECTED_DM="${DM_AVAILABLE[$sel]}" && echo -e "${GREEN}Enabling DM: $SELECTED_DM${NC}" && for d in ly lemurs gdm sddm lightdm; do run "sudo systemctl disable --now '${d}.service' 2>/dev/null || true"; done && run "sudo systemctl enable --now '${SELECTED_DM}.service'"
    fi
  fi
fi

# -----------------------
# Final touches
# -----------------------
echo -e "${GREEN}==> Updating TLDR and user directories...${NC}"
run "tldr --update" || true
run "xdg-user-dirs-update" || true

echo -e "${YELLOW}=======================================${NC}"
echo -e "${GREEN}✓ Full setup complete!${NC}"
echo -e "${YELLOW}=======================================${NC}"