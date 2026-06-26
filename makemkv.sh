#!/bin/bash
set -e

# Detect Package Manager & Install Dependencies
install_deps() {
    if command -v pacman &>/dev/null; then
        echo "Detected: Arch Linux"
        sudo pacman -S --needed --noconfirm \
            base-devel pkgconf openssl expat ffmpeg mesa qt5-base \
            libdvdread libdvdnav libdvdcss libbluray libaacs dvd+rw-tools
: ' Coming Soon
    elif command -v apt &>/dev/null; then
        echo "Detected: Debian/Ubuntu"

'
    elif command -v dnf &>/dev/null; then
        echo "Detected: Fedora/RHEL"
        
        # Check if dnf5 or dnf.
        DNF_VERSION=$(/usr/bin/dnf --version 2>&1 | head -1)
        echo "Using: $DNF_VERSION"
        
        # Install RPMFusion repositories Free & Non Free.
        echo "Installing RPMFusion repositories..."
        sudo dnf install -y \
            https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
            https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

        # Install development tools
        echo "Installing development tools..."
        
        # trying dnf5 syntax, fall back to dnf.
        if sudo dnf group install -y "C Development Tools and Libraries" 2>/dev/null; then
            echo "Using dnf5 group install syntax..."
            sudo dnf group install -y "Development Tools"
        else
            echo "Using dnf groupinstall syntax..."
            sudo dnf groupinstall -y "C Development Tools and Libraries" 2>/dev/null || true
            sudo dnf groupinstall -y "Development Tools" 2>/dev/null || true
        fi

        # Install specific dependencies
        echo "Installing dependencies..."
        sudo dnf install -y zlib-devel openssl-devel expat-devel ffmpeg ffmpeg-devel qt5-qtbase-devel || \
        sudo dnf install -y --allowerasing zlib-devel openssl-devel expat-devel ffmpeg ffmpeg-devel qt5-qtbase-devel

    else
        echo "ERROR: Unsupported distribution."
        echo "Supported: Arch Linux, Debian/Ubuntu, Fedora/RHEL"
        exit 1
    fi
}

# Check if MakeMKV is already installed
check_installed() {
    if which makemkv &>/dev/null; then
        echo " ✔  MakeMKV is already installed"
        return 0
    else
        return 1
    fi
}

# Get Latest Version
get_latest_version() {
    LATEST=$(curl -s https://www.makemkv.com/download/ | grep -oP '(?<=makemkv-bin-)[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.gz)' | head -1)

    # Fallback method
    if [ -z "$LATEST" ]; then
        LATEST=$(curl -s https://www.makemkv.com/download/ | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi

    # Exit if still empty
    if [ -z "$LATEST" ]; then
        echo "ERROR: Could not determine latest version."
        echo "Check https://www.makemkv.com/download/ and set LATEST manually."
        exit 1
    fi

    echo "Latest MakeMKV version: $LATEST"
}

# Fetch & Apply Beta Key
import_beta_key() {
    echo "──────────────────────────────────"
    echo "  Fetching MakeMKV Beta Key"
    echo "──────────────────────────────────"
    echo ""
    echo "Source: https://forum.makemkv.com/forum/viewtopic.php?f=5&t=1053"
    echo ""

    # Get the beta key from the forum page
    # The key is inside a <code> block and starts with T-
    BETA_KEY=$(curl -s "https://forum.makemkv.com/forum/viewtopic.php?f=5&t=1053" | \
        grep -oP '(?<=<code>)[^<]*T-[A-Za-z0-9_]+[^<]*(?=</code>)' | \
        tr -d ' \n\r\t' | \
        head -1)

    # Fallback: broader search for T- pattern
    if [ -z "$BETA_KEY" ]; then
        echo "Trying fallback key extraction..."
        BETA_KEY=$(curl -s "https://forum.makemkv.com/forum/viewtopic.php?f=5&t=1053" | \
            grep -oP 'T-[A-Za-z0-9_]{60,}' | \
            head -1)
    fi

    # Check if we got the key
    if [ -z "$BETA_KEY" ]; then
        echo "⚠ Could not automatically fetch the beta key."
        echo ""
        echo "Please visit:"
        echo "  https://forum.makemkv.com/forum/viewtopic.php?f=5&t=1053"
        echo ""
        read -rp "Paste the beta key here (or press Enter to skip): " BETA_KEY
        
        if [ -z "$BETA_KEY" ]; then
            echo "Skipping key import."
            return 0
        fi
    fi

    echo "✔ Beta key found: $BETA_KEY"
    echo ""

    # Apply the key to MakeMKV settings
    apply_beta_key "$BETA_KEY"
}

# Apply Beta Key to MakeMKV Config
apply_beta_key() {
    local KEY="$1"
    
    # MakeMKV config directory and file
    local CONFIG_DIR="$HOME/.MakeMKV"
    local CONFIG_FILE="$CONFIG_DIR/settings.conf"

    echo "Applying beta key to MakeMKV settings..."

    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"

    # Check if settings.conf already exists
    if [ -f "$CONFIG_FILE" ]; then
        # Check if a key already exists in the config
        if grep -q "^app_Key" "$CONFIG_FILE"; then
            # Update existing key
            sed -i "s|^app_Key.*|app_Key = \"$KEY\"|" "$CONFIG_FILE"
            echo "✔ Beta key updated in existing config"
        else
            # Append key to existing config
            echo "app_Key = \"$KEY\"" >> "$CONFIG_FILE"
            echo "✔ Beta key added to existing config"
        fi
    else
        # Create new config file with the key
        echo "app_Key = \"$KEY\"" > "$CONFIG_FILE"
        echo "✔ New config created with beta key"
    fi

    echo ""
    echo "──────────────────────────────────"
    echo " Beta key applied successfully!   "
    echo " Key: $KEY                        "
    echo " Config: $CONFIG_FILE             "
    echo "──────────────────────────────────"
    echo ""
}

# Download using only curl
download_file() {
    local url="$1"
    local filename="$2"
    
    echo "Downloading $filename..."
    
    # Use curl with explicit options
    curl -C - -L --progress-bar --fail --show-error "$url" -o "$filename"
    
    if [ ! -f "$filename" ]; then
        echo "ERROR: File was not downloaded!"
        exit 1
    fi
    
    # Check file size
    local filesize=$(stat -c%s "$filename" 2>/dev/null || stat -f%z "$filename" 2>/dev/null || echo "0")
    echo "Downloaded file size: $filesize bytes"
    
    # Verify file is a valid tar.gz
    echo "Checking file type..."
    local filetype=$(file "$filename")
    echo "File type: $filetype"
    
    if ! echo "$filetype" | grep -q "gzip compressed data"; then
        echo "ERROR: Downloaded file is not a valid gzip archive!"
        echo "Full file info: $filetype"
        rm -f "$filename"
        exit 1
    fi
    
    echo "✔ $filename downloaded and verified successfully"
}

# Download the latest version
download_makemkv() {
    download_file "https://www.makemkv.com/download/makemkv-oss-${LATEST}.tar.gz" "makemkv-oss-${LATEST}.tar.gz"
    download_file "https://www.makemkv.com/download/makemkv-bin-${LATEST}.tar.gz" "makemkv-bin-${LATEST}.tar.gz"
}

# Build & Install OSS and BIN archives
build_makemkv() {
    # OSS (open source components) first
    echo "Extracting and building makemkv-oss-${LATEST}..."
    tar xzf "makemkv-oss-${LATEST}.tar.gz"
    cd "makemkv-oss-${LATEST}"
    ./configure
    make
    sudo make install
    cd ..

    echo "Extracting and building makemkv-bin-${LATEST}..."
    tar xzf "makemkv-bin-${LATEST}.tar.gz"
    cd "makemkv-bin-${LATEST}"

    # Accept EULA
    echo "yes" | make

    sudo make install
    cd ..
}

# Uninstall
uninstall_makemkv() {
    echo "──────────────────────────────────"
    echo "      Uninstalling MakeMKV...     "
    echo "──────────────────────────────────"

    if ! check_installed; then
        echo "MakeMKV is not installed. Nothing to uninstall."
        return
    fi

    FOUND_BUILD=0
    for DIR in ~/Downloads/makemkv/makemkv-bin-* ~/Downloads/makemkv/makemkv-oss-*; do
        if [ -d "$DIR" ] && [ -f "$DIR/Makefile" ]; then
            echo "Running make uninstall in $DIR..."
            cd "$DIR"
            sudo make uninstall || true
            cd ~
            FOUND_BUILD=1
        fi
    done

    if [ "$FOUND_BUILD" -eq 0 ]; then
        echo "No build directories found. Removing files manually..."
    fi

    echo "Removing MakeMKV files..."
    sudo rm -f \
        /usr/bin/makemkv \
        /usr/bin/makemkvcon \
        /usr/bin/mmccextr \
        /usr/bin/mmgplsrv \
        /usr/bin/sdftool
    sudo rm -rf /usr/share/MakeMKV
    rm -rf ~/.MakeMKV

    echo "──────────────────────────────────"
    echo "   MakeMKV successfully removed!  "
    echo "──────────────────────────────────"
}

# Update Beta Key Only
update_key() {
    echo "──────────────────────────────────"
    echo "    Updating MakeMKV Beta Key     "
    echo "──────────────────────────────────"

    if ! check_installed; then
        echo "MakeMKV is not installed. Please install it first."
        return
    fi

    import_beta_key
}

# Install Flow
install_makemkv() {
    echo "──────────────────────────────────"
    echo "       Installing MakeMKV...      "
    echo "──────────────────────────────────"

    if check_installed; then
        read -rp "MakeMKV is already installed. Do you want to reinstall? (y/n): " REINSTALL
        if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            return
        fi
    fi

    mkdir -p ~/Downloads/makemkv && cd ~/Downloads/makemkv

    install_deps
    get_latest_version
    download_makemkv
    build_makemkv

    # Import beta key after installation
    import_beta_key

    echo "Cleaning up build files..."
    cd ~
    rm -rf ~/Downloads/makemkv

    echo "──────────────────────────────────"
    echo "     MakeMKV $LATEST installed!   "
    echo "──────────────────────────────────"
}

# Menu
menu() {
    clear
    echo "╭────────────────────────────────┐"
    echo "│     MakeMKV Installer Menu     │"
    echo "└────────────────────────────────╯"

    if check_installed; then
        echo "──────────────────────────────────"
        INSTALLED=true
        echo " 1) Reinstall MakeMKV"
        echo " 2) Uninstall MakeMKV"
        echo " 3) Update Beta Key"
        echo " 4) Exit"
    else
        INSTALLED=false
        echo ""
        echo " 1) Install MakeMKV"
        echo " 2) Uninstall MakeMKV"
        echo " 3) Update Beta Key"
        echo " 4) Exit"
    fi

    echo "──────────────────────────────────"
    read -rp "Please choose an option [1-4]: " CHOICE

    case "$CHOICE" in
        1) install_makemkv ;;
        2) uninstall_makemkv ;;
        3) update_key ;;
        4) echo "Bye!"; exit 0 ;;
        *) echo "Invalid option. Please choose 1, 2, 3 or 4."; menu ;;
    esac
}

menu
