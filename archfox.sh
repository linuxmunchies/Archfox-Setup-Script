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
  if pacman -S --needed --noconfirm $package; then
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
    # Install git and base-devel if not already installed
    pacman -S --needed --noconfirm git base-devel

    # Switch to the ACTUAL_USER and install yay
    su - $ACTUAL_USER << EOF
      git clone https://aur.archlinux.org/yay.git /tmp/yay-install
      cd /tmp/yay-install
      makepkg -si --noconfirm
EOF

    # Clean up
    rm -rf /tmp/yay-install

    log_message "yay installed successfully"
  else
    log_message "yay is already installed"
  fi
}

# Function to take a Snapshot
snapshot_function() {
  # Check if filesystem is btrfs
  if [ "$(findmnt -no FSTYPE /)" != "btrfs" ]; then
    log_message "Not using BTRFS filesystem, skipping snapshot setup"
    return
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

# Setup game drive mount function
setup_gamedrive_mount() {
  log_message "Setting up game drive mount..."

  # Set mount details
  GAME_DRIVE_UUID="6c52f6b5-b3f3-49c6-a7cc-2793741afe35"
  MOUNT_POINT="/mnt/gamedrive"
  MOUNT_OPTIONS="rw,relatime,compress=zstd:3,nofail"
  FSTAB_ENTRY="UUID=$GAME_DRIVE_UUID $MOUNT_POINT btrfs $MOUNT_OPTIONS 0 0"

  # Check if drive exists using UUID
  if ! blkid -U "$GAME_DRIVE_UUID" > /dev/null 2>&1; then
    log_message "Game drive with UUID $GAME_DRIVE_UUID not detected, skipping mount setup"
    return 0
  fi

  log_message "Game drive detected, proceeding with mount setup"

  # Create mount point if it doesn't exist
  if ! [ -d "$MOUNT_POINT" ]; then
    log_message "Creating mount point at $MOUNT_POINT"
    sudo mkdir -p "$MOUNT_POINT"
  fi

  # Mount the drive if not already mounted
  if ! mount | grep -q "$MOUNT_POINT"; then
    log_message "Mounting game drive to $MOUNT_POINT"
    sudo mount -U "$GAME_DRIVE_UUID" "$MOUNT_POINT" -o "$MOUNT_OPTIONS"
    if [ $? -ne 0 ]; then
      log_message "ERROR: Failed to mount game drive"
      return 1
    fi
  else
    log_message "Game drive already mounted to $MOUNT_POINT"
  fi

  # Add to fstab if not already there
  if ! grep -q "$GAME_DRIVE_UUID" /etc/fstab; then
    log_message "Adding game drive to /etc/fstab for auto-mount on boot"
    echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab > /dev/null
  else
    log_message "Game drive already in /etc/fstab"
  fi
  systemctl daemon-reload
  log_message "Game drive mounted successfully and set up for auto-mount on boot"
  return 0
}
# Setup game drive mount function
setup_gamedrive_mount() {
  log_message "Setting up game drive mount..."

  # Set mount details
  GAME_DRIVE_UUID="6c52f6b5-b3f3-49c6-a7cc-2793741afe35"
  MOUNT_POINT="/mnt/gamedrive"
  MOUNT_OPTIONS="rw,relatime,compress=zstd:3,nofail"
  FSTAB_ENTRY="UUID=$GAME_DRIVE_UUID $MOUNT_POINT btrfs $MOUNT_OPTIONS 0 0"

  # Check if drive exists using UUID
  if ! blkid -U "$GAME_DRIVE_UUID" > /dev/null 2>&1; then
    log_message "Game drive with UUID $GAME_DRIVE_UUID not detected, skipping mount setup"
    return 0
  fi

  log_message "Game drive detected, proceeding with mount setup"

  # Create mount point if it doesn't exist
  if ! [ -d "$MOUNT_POINT" ]; then
    log_message "Creating mount point at $MOUNT_POINT"
    sudo mkdir -p "$MOUNT_POINT"
  fi

  # Mount the drive if not already mounted
  if ! mount | grep -q "$MOUNT_POINT"; then
    log_message "Mounting game drive to $MOUNT_POINT"
    sudo mount -U "$GAME_DRIVE_UUID" "$MOUNT_POINT" -o "$MOUNT_OPTIONS"
    if [ $? -ne 0 ]; then
      log_message "ERROR: Failed to mount game drive"
      return 1
    fi
  else
    log_message "Game drive already mounted to $MOUNT_POINT"
  fi

  # Add to fstab if not already there
  if ! grep -q "$GAME_DRIVE_UUID" /etc/fstab; then
    log_message "Adding game drive to /etc/fstab for auto-mount on boot"
    echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab > /dev/null
  else
    log_message "Game drive already in /etc/fstab"
  fi

  log_message "Game drive mounted successfully and set up for auto-mount on boot"
  return 0
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
  FSTAB_ENTRY="$SHARE $MOUNT_POINT rw,noserverino,cifs credentials=$CREDENTIALS_FILE,vers=3.0,uid=gitfox,gid=gitfox,nofail 0 0"
  FSTAB_ENTRY2="$SHARE2 $MOUNT_POINT2 cifs rw,noserverino,credentials=$CREDENTIALS_FILE,vers=3.0,uid=gitfox,gid=gitfox,nofail 0 0"

  # Install cifs-utils
  install_package "smbclient cifs-utils"

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
  install_package "ffmpeg yt-dlp vlc mpv strawberry mediainfo flac lame libmpeg2 wavpack x264 x265 gstreamer gst-libav gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly"

  # Install Chinese, Japanese, and Koren Language Support
  install_package "noto-fonts-cjk"

  # Install Multimedia flatpak applications!
  flatpak install com.github.iwalton3.jellyfin-media-player tv.plex.PlexDesktop com.plexamp.Plexamp org.kde.gwenview com.obsproject.Studio org.nickvision.tubeconverter

  # Hardware acceleration
  install_package "intel-media-driver libva-intel-driver" # Intel
  install_package "libva-mesa-driver mesa-vdpau" # AMD

  log_message "Multimedia setup completed successfully"
}

# Setup virtualization function
setup_virtualization() {
  log_message "Setting up virtualization..."

  # Install virtualization packages
  install_package "qemu-full samba libvirt virt-manager dnsmasq"

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
  install_package "amdgpu_top intel-gpu-tools bluez-utils duf fastfetch flatpak btop htop exfatprogs rsync inxi fzf ncdu tmux git wget curl kitty bat make unzip unrar vim wl-clipboard gcc go tldr zsh partitionmanager"

  # Install Essential Flatpaks
  flatpak install net.nokyan.Resources im.riot.Riot io.github.dimtpap.coppwr org.nickvision.cavalier org.telegram.desktop com.rustdesk.RustDesk com.github.unrud.VideoDownloader com.github.tchx84.Flatseal org.kde.kwalletmanager5 -y
  # Install rclone
  log_message "Installing rclone..."
  if ! (sudo -v && curl https://rclone.org/install.sh | sudo bash); then
      log_message "ERROR: Failed to install rclone"
  fi

  # Install Rust
  log_message "Installing rust..."
  if ! (sudo -v && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -sSf | sh); then
      log_message "Error: Failed to install rust!"
  fi
  log_message "Essential applications installed successfully"

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

  # Install Flatpak browsers
  flatpak install -y io.gitlab.librewolf-community

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
  flatpak install -y org.gimp.GIMP flathub org.onlyoffice.desktopeditors md.obsidian.Obsidian net.ankiweb.Anki
  install_package "kate"
  log_message "Office applications installed successfully"
}

# Install gaming applications function
install_gaming() {
  if [ "$INSTALL_GAMING" != "true" ]; then
    log_message "Skipping gaming applications"
    return
  fi

  log_message "Installing gaming applications..."

  # Install rocm packages
  install_package "rocm-core rocm-hip-libraries rocm-hip-runtime rocm-hip-sdk rocm-ml-libraries rocm-ml-sdk rocm-opencl-runtime rocm-opencl-sdk"

  # Install Steam
  install_package "steam"

  # Install mangohud and gamemode
  install_package "lib32-mangohud mangohud gamemode lib32-gamemode"

  # Install gaming apps from Flathub
  flatpak install -y flathub net.lutris.Lutris com.heroicgameslauncher.hgl org.yuzu_emu.yuzu

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

# Mkdirs for ProtonDrive Function
mkdir_proton() {
  mkdir -p ~/ProtonDrive/Archives/{Discord,Obsidian} ~/ProtonDrive/Career/MainDocs/ && chown gitfox:gitfox ~/ProtonDrive/*
}

# Generate summary function
generate_summary() {
  log_message "Generating setup summary..."

  echo "=== Setup Summary ==="
  echo "Setup completed at: $(date)"
  echo "Created with ❤️ for Arch Linux"

  # Display system info
  if command -v fastfetch &> /dev/null; then
    fastfetch
  fi
}

setup_flatpak() {
  log_message "Setting up Flatpak..."
  install_package "flatpak"
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak update
  log_message "Flatpak setup completed"
}

change_to_zsh() {
    # Check if Zsh is installed
    if ! command -v zsh &> /dev/null; then
        echo "Zsh is not installed."
        install_package "zsh"
    fi

    # Change shell for the specified user
    echo "Changing shell for user $ACTUAL_USER to Zsh..."
    sudo chsh -s "$(which zsh)" "$ACTUAL_USER"

    echo "Shell change complete. Please restart your terminal or log out and back in."
}

configure_zshrc() {
    local zshrc="$ACTUAL_HOME/.zshrc"
    local backup="$ACTUAL_HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"

    # Check if .zshrc exists and create backup
    if [[ -f "$zshrc" ]]; then
        echo "Creating backup of existing .zshrc at $backup"
        cp "$zshrc" "$backup"
    else
        echo "No existing .zshrc found, creating a new one"
        touch "$zshrc"
    fi

    # Add keybindings section if it doesn't exist
    if ! grep -q "# Key bindings" "$zshrc"; then
        echo -e "\n# Key bindings" >> "$zshrc"
        echo "bindkey -e" >> "$zshrc"  # Use emacs-style keybindings as a base

        # Define key array for compatibility
        echo "typeset -g -A key" >> "$zshrc"

        # Fix Home/End keys
        echo "bindkey '^[[H' beginning-of-line" >> "$zshrc"
        echo "bindkey '^[[F' end-of-line" >> "$zshrc"
        echo "bindkey '^[[1~' beginning-of-line" >> "$zshrc"  # Alternative Home key
        echo "bindkey '^[[4~' end-of-line" >> "$zshrc"        # Alternative End key
        echo "bindkey '^[OH' beginning-of-line" >> "$zshrc"   # Another alternative
        echo "bindkey '^[OF' end-of-line" >> "$zshrc"         # Another alternative

        # Fix Delete key
        echo "bindkey '^[[3~' delete-char" >> "$zshrc"

        # Page Up/Down
        echo "bindkey '^[[5~' up-line-or-history" >> "$zshrc"
        echo "bindkey '^[[6~' down-line-or-history" >> "$zshrc"

        # Arrow keys for history search
        echo "bindkey '^[[A' up-line-or-search" >> "$zshrc"   # Up arrow
        echo "bindkey '^[[B' down-line-or-search" >> "$zshrc" # Down arrow
        echo "bindkey '^[[C' forward-char" >> "$zshrc"        # Right arrow
        echo "bindkey '^[[D' backward-char" >> "$zshrc"       # Left arrow

        echo "Keybindings added to .zshrc"
    else
        echo "Keybindings section already exists, skipping"
    fi

    # Add useful aliases and functions if they don't exist
    if ! grep -q "# Useful aliases and functions" "$zshrc"; then
        echo -e "\n# Useful aliases and functions" >> "$zshrc"

        # Add 'take' function to create and cd into a directory
        echo "# Create a directory and cd into it" >> "$zshrc"
        echo "function take() {" >> "$zshrc"
        echo "  mkdir -p \$1" >> "$zshrc"
        echo "  cd \$1" >> "$zshrc"
        echo "}" >> "$zshrc"

        # Enable auto-cd (just type directory name to cd into it)
        echo -e "\n# Enable auto-cd" >> "$zshrc"
        echo "setopt auto_cd" >> "$zshrc"

        # Enhance history settings
        echo -e "\n# History settings" >> "$zshrc"
        echo "HISTSIZE=10000" >> "$zshrc"
        echo "SAVEHIST=10000" >> "$zshrc"
        echo "HISTFILE=~/.zsh_history" >> "$zshrc"
        echo "setopt share_history" >> "$zshrc"
        echo "setopt hist_ignore_dups" >> "$zshrc"

        echo '# Arch Linux package management' >> "$zshrc"
        echo 'alias pacupdate="sudo pacman -Syu"' >> "$zshrc"
        echo 'alias pacinstall="sudo pacman -S"' >> "$zshrc"
        echo 'alias pacremove="sudo pacman -Rs"' >> "$zshrc"
        echo 'alias pacsearch="pacman -Ss"' >> "$zshrc"

        echo "Useful aliases and functions added to .zshrc"
    else
        echo "Useful aliases and functions section already exists, skipping"
    fi

    echo "Setup complete! Please restart your terminal or run 'source ~/.zshrc' to apply changes."
}


# Main script execution
log_message "Starting Arch Linux setup script..."

# Execute functions in sequence
root_check
setup_aur_helper
setup_flatpak
snapshot_function
system_upgrade
configure_system
install_kickstart_nvim
setup_multimedia
setup_virtualization
install_essentials
install_browsers
install_office
install_gaming
setup_gamedrive_mount
setup_cifs_mount
mkdir_proton
change_to_zsh
configure_zshrc
cleanup
generate_summary


log_message "Arch Linux setup script completed successfully"
