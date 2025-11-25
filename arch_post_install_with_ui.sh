#!/usr/bin/env bash
# arch_post_install_pacman_aur.sh
# Safe interactive Arch installer (Pacman + AUR)
# Features:
#  - Installs official pacman packages (interactive or --yes)
#  - Installs AUR packages via yay (installs yay if missing)
#  - Clones multiple repos (dotfiles, wallpapers, fonts)
#  - Interactive stow package selection with automatic conflict resolving (stow --adopt)
#  - Interactive WM & DM selection; installs .desktop files
#  - Options: --yes (noninteractive), --dry-run, --verbose
#
# Review the PACKAGES and AUR_PACKAGES arrays and adjust before running.

set -euo pipefail

# ---------------------------
# Options
# ---------------------------
NONINTERACTIVE=false
VERBOSE=false
DRYRUN=false

for arg in "$@"; do
  case "$arg" in
    --yes) NONINTERACTIVE=true ;;
    --verbose) VERBOSE=true ;;
    --dry-run) DRYRUN=true ;;
    *) ;;
  esac
done

log() { [[ "$VERBOSE" == true ]] && echo -e "$*"; }
run() {
  if [[ "$DRYRUN" == true ]]; then
    echo "[DRY-RUN] $*"
  else
    bash -c "$*"
  fi
}

# ---------------------------
# Config: repos to clone (url and dest relative to $HOME)
# Edit these to match your actual repos.
# ---------------------------
REPOS=(
  "https://github.com/kakasia66/dotfiles.git .dotfiles"
  "https://github.com/kakasia66/wallpapers.git Wallpapers"
  "https://github.com/kakasia66/Fonts.git Fonts"
)

# ---------------------------
# Default packages (edit to taste)
# ---------------------------
PACKAGES=(
  base-devel git stow alacritty neovim starship curl wget unzip htop man-db tldr
  fastfetch eza xorg xdg-user-dirs bash-completion brightnessctl pamixer lm_sensors
)

# Add ly as optional display manager package if you want
DM_PACKAGES=(ly)

# AUR packages to install (edit)
AUR_PACKAGES=(
  brave-bin blesh-git
)

# ---------------------------
# Helpers
# ---------------------------
abort() { echo -e "\e[31mERROR:\e[0m $*" >&2; exit 1; }
confirm() {
  # returns 0 for yes, 1 for no
  if [[ "$NONINTERACTIVE" == true ]]; then
    return 0
  fi
  read -rp "$1 [y/N]: " ans
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------
# Ensure yay (AUR helper) installed
# ---------------------------
install_yay_if_missing() {
  if command -v yay &>/dev/null; then
    log "yay is present."
    return
  fi
  echo "yay not found. Installing yay..."
  run "sudo pacman -S --needed --noconfirm git base-devel"
  TMPDIR=$(mktemp -d)
  run "git clone https://aur.archlinux.org/yay.git '$TMPDIR/yay'"
  # build inside TMPDIR
  run "cd '$TMPDIR/yay' && makepkg -si --noconfirm"
  run "rm -rf '$TMPDIR'"
  # return to safe dir
  cd "$HOME"
}

# ---------------------------
# Clone multiple repos
# ---------------------------
clone_repos() {
  echo "Cloning repos..."
  for entry in "${REPOS[@]}"; do
    url=$(awk '{print $1}' <<<"$entry")
    dest=$(awk '{print $2}' <<<"$entry")
    dest_path="$HOME/$dest"
    if [[ -d "$dest_path" ]]; then
      echo " - $dest already exists, pulling..."
      run "git -C '$dest_path' pull --rebase || true"
    else
      echo " - Cloning $url → $dest_path"
      run "git clone '$url' '$dest_path'"
    fi
  done
}

# ---------------------------
# Stow helpers with automatic adopt
# ---------------------------
ensure_stow() {
  if ! command -v stow &>/dev/null; then
    echo "stow missing — installing..."
    run "sudo pacman -S --needed --noconfirm stow"
  fi
}

choose_stow_packages_interactive() {
  if [[ ! -d "$HOME/.dotfiles" ]]; then
    echo "No $HOME/.dotfiles found, skipping stow selection."
    SELECTED_STOW=()
    return
  fi
  echo "Available stow packages in ~/.dotfiles:"
  pushd "$HOME/.dotfiles" >/dev/null
  mapfile -t ALL_PKGS < <(find . -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
  popd >/dev/null
  if [[ ${#ALL_PKGS[@]} -eq 0 ]]; then
    echo "No packages found in ~/.dotfiles"
    SELECTED_STOW=()
    return
  fi
  for i in "${!ALL_PKGS[@]}"; do
    echo " $((i+1))) ${ALL_PKGS[$i]}"
  done
  echo " 0) Done / Finish selection"
  SELECTED_STOW=()
  while true; do
    read -rp "Select package number to add (0 to finish): " choice
    if [[ "$choice" == "0" ]]; then break; fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ALL_PKGS[@]} )); then
      p="${ALL_PKGS[$((choice-1))]}"
      if [[ " ${SELECTED_STOW[*]} " =~ " $p " ]]; then
        echo "Already selected."
      else
        SELECTED_STOW+=("$p")
        echo "Selected: $p"
      fi
    else
      echo "Invalid selection."
    fi
  done
}

stow_with_auto_adopt() {
  # requires: SELECTED_STOW array
  if [[ ${#SELECTED_STOW[@]} -eq 0 ]]; then
    echo "No stow packages selected; skipping."
    return
  fi

  pushd "$HOME/.dotfiles" >/dev/null
  for pkg in "${SELECTED_STOW[@]}"; do
    echo "Stowing: $pkg"
    if stow "$pkg" 2>/tmp/stow_err; then
      echo " - OK"
      rm -f /tmp/stow_err || true
      continue
    fi
    err=$(< /tmp/stow_err)
    # detect conflict wording and attempt adopt
    if grep -q -i "would cause conflicts" /tmp/stow_err || grep -q "existing target" /tmp/stow_err; then
      echo " - Conflict detected. Will attempt to adopt existing files into the package and stow."
      # show conflicts for user and ask permission if interactive
      if [[ "$NONINTERACTIVE" == false ]]; then
        echo "Conflicts:"
        echo "$err"
      fi
      if confirm "Adopt conflicting files into $pkg and continue?"; then
        echo " - Adopting..."
        stow --adopt "$pkg"
      else
        echo " - Skipping $pkg by user choice."
      fi
    else
      echo " - Unexpected stow error:"
      echo "$err"
      rm -f /tmp/stow_err || true
      if confirm "Abort script due to stow error?"; then
        abort "User requested abort due to stow error"
      fi
    fi
    rm -f /tmp/stow_err || true
  done
  popd >/dev/null
}

# ---------------------------
# WM / DM interactive steps
# ---------------------------
choose_wm_and_install_desktop() {
  echo "Choose a Window Manager to create a session for (or press Enter to skip):"
  WMS=("dwm" "i3" "bspwm" "openbox" "xmonad" "sway" "hyprland")
  for i in "${!WMS[@]}"; do
    echo " $((i+1))) ${WMS[$i]}"
  done
  read -rp "WM number (blank to skip): " wm_choice
  if [[ -z "$wm_choice" ]]; then
    SELECTED_WM=""
    return
  fi
  if ! [[ "$wm_choice" =~ ^[0-9]+$ ]] || (( wm_choice < 1 || wm_choice > ${#WMS[@]} )); then
    echo "Invalid choice; skipping."
    SELECTED_WM=""
    return
  fi
  SELECTED_WM="${WMS[$((wm_choice-1))]}"
  echo "Selected WM: $SELECTED_WM"

  # find exec path heuristics
  execpath=""
  # common default map
  declare -A DEFAULT_EXEC=( [dwm]="/usr/local/bin/dwm" [i3]="/usr/bin/i3" [bspwm]="/usr/bin/bspwm" [openbox]="/usr/bin/openbox-session" [xmonad]="/usr/bin/xmonad" [sway]="/usr/bin/sway" [hyprland]="/usr/bin/Hyprland" )
  if [[ -n "${DEFAULT_EXEC[$SELECTED_WM]:-}" && -x "${DEFAULT_EXEC[$SELECTED_WM]}" ]]; then
    execpath="${DEFAULT_EXEC[$SELECTED_WM]}"
  else
    # check dotfiles for start script
    candidates=( "$HOME/.dotfiles/start-$SELECTED_WM" "$HOME/.dotfiles/scripts/start-$SELECTED_WM" "$HOME/.dotfiles/$SELECTED_WM/start" "$HOME/.dotfiles/$SELECTED_WM/run" )
    for c in "${candidates[@]}"; do
      if [[ -f "$c" ]]; then
        execpath="$c"
        chmod +x "$c" 2>/dev/null || true
        break
      fi
    done
  fi

  if [[ -z "$execpath" ]]; then
    if confirm "No executable found automatically for $SELECTED_WM. Enter custom Exec command now?"; then
      read -rp "Exec: " execpath
    else
      echo "Skipping .desktop creation for $SELECTED_WM"
      SELECTED_WM=""
      return
    fi
  fi

  # create xsessions/wayland-sessions dir as appropriate
  if [[ "$SELECTED_WM" == "sway" || "$SELECTED_WM" == "hyprland" ]]; then
    SES_DIR="/usr/share/wayland-sessions"
  else
    SES_DIR="/usr/share/xsessions"
  fi

  run "sudo mkdir -p '$SES_DIR'"
  DESKTOP_PATH="$SES_DIR/$SELECTED_WM.desktop"
  DESKTOP_CONTENT="[Desktop Entry]
Name=$SELECTED_WM
Comment=Start $SELECTED_WM session
Exec=$execpath
Type=Application
DesktopNames=$SELECTED_WM"

  echo "Installing session file to $DESKTOP_PATH"
  run "echo \"$DESKTOP_CONTENT\" | sudo tee '$DESKTOP_PATH' >/dev/null"
  run "sudo chmod 644 '$DESKTOP_PATH'"
  echo "Installed: $DESKTOP_PATH"
}

# ---------------------------
# Package installation (Pacman + AUR)
# ---------------------------
install_system_packages_interactive() {
  echo "Install official pacman packages?"
  if [[ "$NONINTERACTIVE" == true ]] || confirm "Proceed to install default pacman packages?"; then
    echo "Installing pacman packages..."
    # install in smaller batches to avoid huge single command problems
    BATCH=()
    for pkg in "${PACKAGES[@]}"; do
      BATCH+=("$pkg")
      if (( ${#BATCH[@]} >= 10 )); then
        run "sudo pacman -S --needed --noconfirm ${BATCH[*]}"
        BATCH=()
      fi
    done
    if (( ${#BATCH[@]} > 0 )); then
      run "sudo pacman -S --needed --noconfirm ${BATCH[*]}"
    fi
  else
    echo "Skipping pacman package installation."
  fi
}

install_aur_packages_interactive() {
  if [[ ${#AUR_PACKAGES[@]} -eq 0 ]]; then
    return
  fi
  install_yay_if_missing
  echo "Install AUR packages?"
  if [[ "$NONINTERACTIVE" == true ]] || confirm "Proceed to install AUR packages?"; then
    for pkg in "${AUR_PACKAGES[@]}"; do
      if pacman -Q "$pkg" &>/dev/null; then
        echo "$pkg already in pacman DB; skipping."
        continue
      fi
      echo "Installing AUR package: $pkg"
      run "yay -S --needed --noconfirm '$pkg'"
    done
  else
    echo "Skipping AUR package installation."
  fi
}

# ---------------------------
# Main flow
# ---------------------------
main() {
  echo "=== Arch post-install (Pacman + AUR) ==="
  # ensure HOME exists and start in HOME to avoid cwd-deletion issues
  cd "$HOME"

  ensure_stow

  install_system_packages_interactive

  install_aur_packages_interactive

  clone_repos

  # stow flow
  if [[ -d "$HOME/.dotfiles" ]]; then
    choose_stow_packages_interactive
    stow_with_auto_adopt
  else
    echo "No ~/.dotfiles found; skipping stow step."
  fi

  # WM / DM
  choose_wm_and_install_desktop

  echo "Finalizing..."
  run "tldr --update" || true
  run "xdg-user-dirs-update" || true

  echo "=== Done ==="
  echo "If you want dry-run or verbose: run with --dry-run and/or --verbose"
}

main "$@"
