#!/bin/bash

# Arch Linux Setup Script

# Define variables for the actual user (not root/sudo)
ACTUAL_USER=gitfox
ACTUAL_HOME=/home/gitfox

# Installation category selection (default: all enabled)
INSTALL_ESSENTIALS=true
INSTALL_BROWSERS=true
INSTALL_OFFICE=true
INSTALL_CODING=true
INSTALL_MEDIA=true
INSTALL_GAMING=true
INSTALL_REMOTE=true
INSTALL_FILESHARING=true
INSTALL_SYSTEMTOOLS=true
INSTALL_CUSTOMIZATION=true

# Root Check Function
root_check() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as sudo"
    exit 1
  fi
}

# Logging function
log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$ACTUAL_HOME/Desktop/arch_setup.log"
}

# Confirm Action Function
confirm_action() {
  read -p "$1 (y/n): " response
  case "$response" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) return 1 ;;
  esac
}

# Error handling function
install_package() {
  local package=$1
  log_message "Installing $package..."
  if pacman -S --noconfirm $package; then
    log_message "$package installed successfully"
  else
    log_message "ERROR: Failed to install $package"
  fi
}

# Setup AUR helper
setup_aur_helper() {
  log_message "Setting up AUR helper (yay)..."

  # Check if yay is already installed
  if ! command -v yay &> /dev/null; then
    # Install git if not already installed
    install_package "git base-devel"

    # Create temp directory and clone yay
    mkdir -p /tmp/yay-install
    cd /tmp/yay-install
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si

    # Clean up
    cd /
    rm -rf /tmp/yay-install
    log_message "yay installed successfully"
  else
    log_message "yay is already installed"
  fi
}

# Function to check if a subvolume exists
check_subvol() {
  sudo btrfs subvolume list / | grep -q -E " path ($1|@$1|@var_$1|var_$1)$"
}

snapshot_function() {
  # Check if filesystem is btrfs
  if [ "$(findmnt -no FSTYPE /)" != "btrfs" ]; then
    log_message "Not using BTRFS filesystem, skipping snapshot setup"
    return
  fi

  # Check critical directories
  log_is_subvol=$(check_subvol "log" && echo "yes" || echo "no")
  cache_is_subvol=$(check_subvol "cache" && echo "yes" || echo "no")

  # Warn if not subvolumes
  if [[ "$log_is_subvol" == "no" || "$cache_is_subvol" == "no" ]]; then
    echo "WARNING: These directories are not BTRFS subvolumes:"
    [[ "$log_is_subvol" == "no" ]] && echo "- /var/log"
    [[ "$cache_is_subvol" == "no" ]] && echo "- /var/cache"
    echo "This will make snapshots larger and may cause issues during rollbacks."
    read -p "Continue anyway? (yes/no): " answer
    if [[ "$answer" != "yes" ]]; then
      echo "Script terminated."
      exit 1
    fi
  fi

  # Create snapshots
  echo "Creating system snapshots..."
  DATE=$(date +%Y-%m-%d-%H-%M-%S)

  # Install snapper
  install_package "snapper"

  # Enable and start snapper services
  systemctl enable --now snapper-timeline.timer snapper-cleanup.timer

  # Create configs if they don't exist
  snapper -c root create-config /
  snapper -c home create-config /home

  # Create initial snapshots
  snapper -c root create -d "${DATE}_Root"
  snapper -c home create -d "${DATE}_Home"

  echo "Snapshots created: root-$DATE, home-$DATE"
}

# System upgrade function
system_upgrade() {
  log_message "Performing system upgrade... This may take a while..."

  # Update package database and upgrade all packages
  pacman -Syu --noconfirm

  log_message "System upgrade completed successfully"
}

# System configuration function
configure_system() {
  log_message "Configuring system..."

  # Set hostname
  log_message "Setting hostname..."
  hostnamectl set-hostname ArchFox

  # Optimize pacman configuration
  log_message "Optimizing pacman configuration..."
  cp /etc/pacman.conf /etc/pacman.conf.bak

  # Enable color in pacman output
  sed -i 's/^#Color/Color/' /etc/pacman.conf

  # Set parallel downloads
  if grep -q "^#ParallelDownloads" /etc/pacman.conf; then
    sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
  elif ! grep -q "^ParallelDownloads" /etc/pacman.conf; then
    echo "ParallelDownloads = 10" >> /etc/pacman.conf
  fi

  log_message "pacman configuration updated successfully"

  # Check for firmware updates
  log_message "Checking for firmware updates..."
  install_package "fwupd"
  fwupdmgr refresh --force
  fwupdmgr get-updates
  fwupdmgr update

  log_message "System configuration completed successfully"
}

# Setup CIFS mount function
setup_cifs_mount() {
  log_message "Setting up CIFS mount..."

  # Set mount details
  SHARE="//192.168.0.2/media"
  SHARE2="//192.168.0.2/archives"
  MOUNT_POINT="/mnt/media"
  MOUNT_POINT2="/mnt/archives"
  CREDENTIALS_FILE="/etc/cifs-credentials"
  FSTAB_ENTRY="$SHARE $MOUNT_POINT cifs credentials=$CREDENTIALS_FILE,vers=3.0,uid=gitfox,gid=gitfox,nofail 0 0"
  FSTAB_ENTRY2="$SHARE2 $MOUNT_POINT2 cifs credentials=$CREDENTIALS_FILE,vers=3.0,uid=gitfox,gid=gitfox,nofail 0 0"

  # Install cifs-utils
  install_package "cifs-utils"

  # Prompt for username and password securely
  log_message "Setting up CIFS credentials..."
  read -rp "Enter CIFS username: " CIFS_USER
  read -rsp "Enter CIFS password: " CIFS_PASS
  echo ""

  # Create credentials file securely
  if ! echo -e "username=$CIFS_USER\npassword=$CIFS_PASS" | sudo tee "$CREDENTIALS_FILE" >/dev/null; then
    log_message "ERROR: Failed to create credentials file"
    return 1
  fi
  sudo chmod 600 "$CREDENTIALS_FILE"

  # Create mount points
  mkdir -p "$MOUNT_POINT" "$MOUNT_POINT2"

  # Mount the shares
  mount -t cifs "$SHARE" "$MOUNT_POINT" -o "credentials=$CREDENTIALS_FILE,vers=3.0,uid=gitfox,gid=gitfox,nofail"
  mount -t cifs "$SHARE2" "$MOUNT_POINT2" -o "credentials=$CREDENTIALS_FILE,vers=3.0,uid=gitfox,gid=gitfox,nofail"

  # Add to fstab if not already there
  if ! grep -q "$SHARE" /etc/fstab; then
    echo "$FSTAB_ENTRY" >> /etc/fstab
  fi

  if ! grep -q "$SHARE2" /etc/fstab; then
    echo "$FSTAB_ENTRY2" >> /etc/fstab
  fi

  log_message "CIFS shares mounted successfully and set up for auto-mount on boot"
}

# Setup multimedia codecs function
setup_multimedia() {
  log_message "Setting up multimedia support..."

  # Install multimedia codecs for Arch
  install_package "a52dec faac faad2 flac jasper lame libdca libdv libmad libmpeg2 libtheora libvorbis libvpx libxv wavpack x264 x265 xvidcore gstreamer gstreamer-plugins-base gstreamer-plugins-good gstreamer-plugins-bad gstreamer-plugins-ugly"

  # Hardware acceleration
  install_package "intel-media-driver libva-intel-driver" # Intel
  install_package "libva-mesa-driver mesa-vdpau" # AMD

  log_message "Multimedia setup completed successfully"
}

# Setup virtualization function
setup_virtualization() {
  log_message "Setting up virtualization..."

  # Install virtualization packages
  install_package "qemu libvirt virt-manager ebtables dnsmasq bridge-utils"

  # Enable and start libvirtd service
  systemctl enable libvirtd
  systemctl start libvirtd

  # Add user to libvirt group
  usermod -aG libvirt $ACTUAL_USER

  log_message "Virtualization setup completed successfully"
}

# Install essential applications function
install_essentials() {
  if [ "$INSTALL_ESSENTIALS" != "true" ]; then
    log_message "Skipping essential applications"
    return
  fi

  log_message "Installing essential applications..."

  # Install packages
  install_package "btop htop rsync inxi fzf ncdu tmux git wget curl kitty bat make unzip gcc go tldr"

  # Install packages that might be in AUR
  su - $ACTUAL_USER -c "yay -S --noconfirm fastfetch duf"

  # Install rclone
  install_package "rclone"

  # Install Rust
  install_package "rustup"
  su - $ACTUAL_USER -c "rustup default stable"

  log_message "Essential applications installed successfully"
}

install_kickstart_nvim() {
  echo "Installing kickstart.nvim"

  # Install Neovim
  install_package "neovim ripgrep fd"

  # Define Neovim config directory
  NVIM_CONFIG_DIR="$ACTUAL_HOME/.config/nvim"

  # Backup existing configuration
  if [ -d "$NVIM_CONFIG_DIR" ]; then
    BACKUP_DIR="$NVIM_CONFIG_DIR.backup.$(date +%Y%m%d%H%M%S)"
    mv "$NVIM_CONFIG_DIR" "$BACKUP_DIR"
  fi

  # Clean Neovim data directories
  rm -rf $ACTUAL_HOME/.local/share/nvim $ACTUAL_HOME/.local/state/nvim $ACTUAL_HOME/.cache/nvim

  # Install kickstart.nvim
  mkdir -p "$NVIM_CONFIG_DIR"
  git clone https://github.com/nvim-lua/kickstart.nvim.git "$NVIM_CONFIG_DIR"
  chown -R $ACTUAL_USER:$ACTUAL_USER "$NVIM_CONFIG_DIR"

  echo "kickstart.nvim installed successfully"
}

# Install browser applications function
install_browsers() {
  if [ "$INSTALL_BROWSERS" != "true" ]; then
    log_message "Skipping browser applications"
    return
  fi

  log_message "Installing browsers and communication apps..."

  # Install Brave browser (via AUR)
  su - $ACTUAL_USER -c "yay -S --noconfirm brave-bin"

  # Install Flatpak browsers
  flatpak install -y flathub io.gitlab.librewolf-community app.zen_browser.zen im.riot.Riot org.telegram.desktop

  log_message "Browser applications installed successfully"
}

# Install office applications function
install_office() {
  if [ "$INSTALL_OFFICE" != "true" ]; then
    log_message "Skipping office applications"
    return
  fi

  log_message "Installing office applications..."[9]

  # Install Office apps from Flathub
  flatpak install -y flathub org.onlyoffice.desktopeditors md.obsidian.Obsidian net.ankiweb.Anki

  log_message "Office applications installed successfully"
}

# Install coding applications function
install_coding() {
  if [ "$INSTALL_CODING" != "true" ]; then
    log_message "Skipping coding applications"
    return
  fi

  log_message "Installing development tools..."

  # Install Docker
  install_package "docker docker-compose"

  # Enable Docker service
  systemctl enable --now docker

  # Add user to Docker group
  groupadd docker 2>/dev/null || true
  usermod -aG docker $ACTUAL_USER

  log_message "Development tools installed successfully"
}

# Install gaming applications function
install_gaming() {
  if [ "$INSTALL_GAMING" != "true" ]; then
    log_message "Skipping gaming applications"
    return
  fi

  log_message "Installing gaming applications..."

  # Install Steam
  install_package "steam"

  # Install mangohud
  install_package "mangohud"

  # Install goverlay from AUR
  su - $ACTUAL_USER -c "yay -S --noconfirm goverlay"

  # Install gaming apps from Flathub
  flatpak install -y flathub net.lutris.Lutris com.heroicgameslauncher.hgl

  log_message "Gaming applications installed successfully"
}

# Cleanup function
cleanup() {
  log_message "Performing cleanup..."

  # Clean up package cache
  pacman -Sc --noconfirm

  # Remove unused Flatpak runtimes
  flatpak uninstall --unused -y

  log_message "Cleanup completed successfully"
}

# Generate summary function
generate_summary() {
  log_message "Generating setup summary..."

  echo "=== Setup Summary ==="
  echo "Hostname: $(hostname)"
  echo "Setup completed at: $(date)"
  echo "Created with ❤️ for Arch Linux"

  # Display system info
  if command -v fastfetch &> /dev/null; then
    fastfetch
  elif command -v neofetch &> /dev/null; then
    neofetch
  fi
}

# Main script execution
log_message "Starting Arch Linux setup script..."

# Execute functions in sequence
root_check
setup_aur_helper
setup_flatpak() {
  log_message "Setting up Flatpak..."
  install_package "flatpak"
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak update
  log_message "Flatpak setup completed"
}

setup_flatpak
snapshot_function
system_upgrade
configure_system
install_kickstart_nvim
setup_cifs_mount
setup_multimedia
setup_virtualization
install_essentials
install_browsers
install_office
install_coding
install_gaming
cleanup
generate_summary

log_message "Arch Linux setup script completed successfully"
