#!/usr/bin/env bash
# ==============================================================================
# ARCH LINUX POST-INSTALL & DOTFILE BOOTSTRAPPER
# ==============================================================================
# Features:
#  - Safe interactive Pacman + AUR (yay) installer
#  - Smart Git cloning (handles existing repos)
#  - Interactive GNU Stow manager with conflict resolution (--adopt)
#  - Intelligent Window Manager / Desktop Session setup
#
# Usage:
#  ./install.sh            (Interactive)
#  ./install.sh --yes      (Non-interactive / Headless)
#  ./install.sh --dry-run  (Print commands without executing)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# [1] USER CONFIGURATION
# (Edit this section to match your preferences)
# ==============================================================================

# Git Repositories to clone
# Format: "URL DESTINATION_FOLDER" (Destination is relative to $HOME)
REPOS=(
  "https://github.com/BehdadBabaie/dotfiles.git .dotfiles"
  "https://github.com/BehdadBabaie/wallpapers.git Wallpapers"
  "https://github.com/BehdadBabaie/Fonts.git Fonts"
)

# Official Arch Packages (Pacman)
PACKAGES=(
   # System & Utils
   base-devel
   linux-headers
   dkms
   bash-completion
   man-db
   tldr
   git
   curl
   wget
   unzip
   htop
   bat
   eza
   fastfetch
   fzf
   stow
   openssh
   xdg-user-dirs
   virtualbox-guest-utils
   
   # Shell & Terminal
   zsh
   starship
   alacritty
   nvim
   
   # UI / X11 / Wayland
   xorg
   xorg-xinit
   ly          # Display Manager
   feh         # Wallpaper
   yazi
   ueberzugpp
   
   # Fonts
   ttf-meslo-nerd
   ttf-firacode-nerd
   ttf-ubuntu-mono-nerd
   ttf-ubuntu-nerd
   
   # WM Dependencies
   xcb-util 
   xcb-util-wm
   xcb-util-xrm
   lm_sensors
   brightnessctl
   pamixer
)

# AUR Packages (Installed via yay)
AUR_PACKAGES=(
  brave-bin 
  blesh-git
)

# ==============================================================================
# [2] CORE LOGIC & HELPERS
# (Do not edit below unless you know what you are doing)
# ==============================================================================

# Global Flags
NONINTERACTIVE=false
VERBOSE=false
DRYRUN=false
TEMP_DIR=""

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Argument Parsing ---
for arg in "$@"; do
  case "$arg" in
    --yes) NONINTERACTIVE=true ;;
    --verbose) VERBOSE=true ;;
    --dry-run) DRYRUN=true ;;
    *) ;;
  esac
done

# --- Logging & execution wrappers ---
log() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

run() {
  if [[ "$DRYRUN" == true ]]; then
    echo -e "${YELLOW}[DRY]${NC} $*"
  else
    [[ "$VERBOSE" == true ]] && echo -e ":: Running: $*"
    bash -c "$*"
  fi
}

confirm() {
  if [[ "$NONINTERACTIVE" == true ]]; then return 0; fi
  read -rp "$1 [y/N]: " ans
  [[ "$ans" =~ ^[Yy] ]]
}

# --- Cleanup Trap ---
cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    [[ "$VERBOSE" == true ]] && log "Cleaning up temp dir: $TEMP_DIR"
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT

# --- Safety Checks ---
pre_flight_checks() {
  if [[ $EUID -eq 0 ]]; then
    error "Do NOT run this script as root/sudo. Run as a normal user.\nThe script will ask for sudo permissions when needed."
  fi
  
  # Refresh sudo credential cache
  log "Requesting sudo privileges for installation steps..."
  sudo -v
}

# ==============================================================================
# [3] FUNCTIONS
# ==============================================================================

install_yay_if_missing() {
  if command -v yay &>/dev/null; then
    success "Yay is already installed."
    return
  fi

  log "Yay not found. Installing..."
  run "sudo pacman -S --needed --noconfirm git base-devel"
  
  # Create a safe temp directory for building
  TEMP_DIR=$(mktemp -d)
  
  if [[ "$DRYRUN" == false ]]; then
    git clone https://aur.archlinux.org/yay.git "$TEMP_DIR/yay"
    pushd "$TEMP_DIR/yay" >/dev/null
    makepkg -si --noconfirm
    popd >/dev/null
  else
    echo "[DRY] Would clone yay to temp and run makepkg"
  fi
}

install_packages() {
  log "System Update & Package Installation"
  
  # 1. Official Pacman Packages
  if [[ ${#PACKAGES[@]} -gt 0 ]]; then
    if confirm "Install ${#PACKAGES[@]} official packages?"; then
      # Convert array to space-separated string
      local pkg_list="${PACKAGES[*]}"
      run "sudo pacman -S --needed --noconfirm $pkg_list"
    else
      warn "Skipping Pacman packages."
    fi
  fi

  # 2. AUR Packages
  if [[ ${#AUR_PACKAGES[@]} -gt 0 ]]; then
    install_yay_if_missing
    if confirm "Install ${#AUR_PACKAGES[@]} AUR packages?"; then
      local aur_list="${AUR_PACKAGES[*]}"
      run "yay -S --needed --noconfirm $aur_list"
    else
      warn "Skipping AUR packages."
    fi
  fi
}

clone_repos() {
  log "Cloning Repositories..."
  for entry in "${REPOS[@]}"; do
    # Safe splitting using read
    read -r url dest <<< "$entry"
    local dest_path="$HOME/$dest"

    if [[ -d "$dest_path" ]]; then
      log "Updating existing: $dest"
      run "git -C '$dest_path' pull --rebase || true"
    else
      log "Cloning: $dest"
      run "git clone '$url' '$dest_path'"
    fi
  done
}

manage_dotfiles_stow() {
  local dotfiles_dir="$HOME/.dotfiles"
  
  # Ensure stow is installed
  if ! command -v stow &>/dev/null; then
    warn "Stow not found. Installing..."
    run "sudo pacman -S --needed --noconfirm stow"
  fi

  if [[ ! -d "$dotfiles_dir" ]]; then
    warn "No $dotfiles_dir found. Skipping stow."
    return
  fi

  log "Preparing to stow dotfiles..."
  pushd "$dotfiles_dir" >/dev/null

  # Get list of directories (packages)
  mapfile -t ALL_PKGS < <(find . -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
  
  if [[ ${#ALL_PKGS[@]} -eq 0 ]]; then
    warn "No packages found in .dotfiles"
    popd >/dev/null; return
  fi

  # Interactive Selection
  local SELECTED_STOW=()
  if [[ "$NONINTERACTIVE" == true ]]; then
    # In non-interactive, assume we want to stow everything? Or skip?
    # Safer to skip or defined specific list. For now, let's log and skip to be safe.
    warn "Non-interactive mode: Skipping stow selection to avoid conflicts."
  else
    echo "Available packages:"
    for i in "${!ALL_PKGS[@]}"; do
      echo " $((i+1))) ${ALL_PKGS[$i]}"
    done
    echo " 0) Done / Finish"

    while true; do
      read -rp "Select package # (0 to finish): " choice
      [[ "$choice" == "0" ]] && break
      if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ALL_PKGS[@]} )); then
        local pkg="${ALL_PKGS[$((choice-1))]}"
        if [[ " ${SELECTED_STOW[*]} " =~ " $pkg " ]]; then
          echo "Already selected."
        else
          SELECTED_STOW+=("$pkg")
          echo "Added: $pkg"
        fi
      fi
    done
  fi

  # Apply Stow
  for pkg in "${SELECTED_STOW[@]}"; do
    log "Stowing: $pkg"
    # Capture stderr to a temp file to parse conflicts
    local stow_log
    stow_log=$(mktemp)
    
    if run "stow '$pkg' 2>'$stow_log'"; then
      success "$pkg stowed successfully."
    else
      # If dry-run, we won't get here usually, but if we do:
      if grep -q "existing target" "$stow_log" || grep -q "conflicts" "$stow_log"; then
        warn "Conflict detected for $pkg."
        if confirm "Adopt existing files (overwrite system with repo)?"; then
          run "stow --adopt '$pkg'"
          # Revert modifications git might see after adopt
          run "git restore ." 
          success "$pkg adopted."
        else
          warn "Skipped $pkg."
        fi
      else
        error "Stow failed with unknown error: $(cat "$stow_log")"
      fi
    fi
    rm -f "$stow_log"
  done

  popd >/dev/null
}

choose_wm_and_install_desktop() {
    echo "-------------------------------------------------"
    echo "Window Manager / Compositor Setup"
    echo "-------------------------------------------------"

    # Define supported WMs and their type (x11 or wayland)
    AVAILABLE_WMS=(
        "dwm:x11"
        "i3:x11"
        "bspwm:x11"
        "openbox:x11"
        "xmonad:x11"
        "sway:wayland"
        "hyprland:wayland"
        "river:wayland"
    )

    echo "Select a Window Manager to configure:"
    for i in "${!AVAILABLE_WMS[@]}"; do
        wm_name="${AVAILABLE_WMS[$i]%%:*}"
        echo " $((i+1))) $wm_name"
    done

    local wm_name=""
    local wm_type=""

    while true; do
        read -rp "Enter number (or press Enter to skip): " choice
        if [[ -z "$choice" ]]; then return; fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#AVAILABLE_WMS[@]} )); then
            local entry="${AVAILABLE_WMS[$((choice-1))]}"
            wm_name="${entry%%:*}"
            wm_type="${entry##*:}"
            break
        fi
    done

    log "Configuring session for: $wm_name ($wm_type)"

    # 1. Find Executable
    local exec_path=""
    if exec_path=$(command -v "$wm_name"); then
        success "Found binary: $exec_path"
    else
        # Check custom scripts in dotfiles
        local candidates=(
            "$HOME/.dotfiles/scripts/start-$wm_name"
            "$HOME/.dotfiles/$wm_name/start"
            "$HOME/.dotfiles/$wm_name/run"
        )
        for c in "${candidates[@]}"; do
            if [[ -f "$c" ]]; then
                exec_path="$c"
                run "chmod +x '$exec_path'"
                break
            fi
        done
    fi

    # Manual override if not found
    if [[ -z "$exec_path" ]]; then
        if confirm "Binary not found. Enter manual path?"; then
            read -rp "Exec command: " exec_path
        else
            warn "Skipping session creation."
            return
        fi
    fi

    # 2. Install .desktop file
    local session_dir="/usr/share/xsessions"
    [[ "$wm_type" == "wayland" ]] && session_dir="/usr/share/wayland-sessions"

    local desktop_entry="[Desktop Entry]
Name=${wm_name^}
Comment=Start $wm_name session
Exec=$exec_path
Type=Application
DesktopNames=$wm_name"

    local target_file="$session_dir/$wm_name.desktop"
    
    run "sudo mkdir -p '$session_dir'"
    
    # We use a temp file strategy to write with sudo
    local tmp_desk
    tmp_desk=$(mktemp)
    echo "$desktop_entry" > "$tmp_desk"
    run "sudo cp '$tmp_desk' '$target_file'"
    run "sudo chmod 644 '$target_file'"
    rm -f "$tmp_desk"

    success "Installed session file at $target_file"
}

finalize() {
  log "Finalizing settings..."
  run "xdg-user-dirs-update" || true
  
  if command -v tldr &>/dev/null; then
    run "tldr --update" || true
  fi

  echo ""
  echo -e "${GREEN}==========================================${NC}"
  echo -e "${GREEN}   INSTALLATION COMPLETE                  ${NC}"
  echo -e "${GREEN}==========================================${NC}"
  echo "Please reboot your system."
}

# ==============================================================================
# [4] MAIN EXECUTION
# ==============================================================================

main() {
  pre_flight_checks
  
  # Go home to ensure relative paths work
  cd "$HOME"

  install_packages
  clone_repos
  manage_dotfiles_stow
  choose_wm_and_install_desktop
  finalize
}

main "$@"