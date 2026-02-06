#!/usr/bin/env bash

#Jacob Mattie
#j_mattie@live.ca

#November, 2025


set -euo pipefail

trap 'echo "ERROR in function ${FUNCNAME[0]:-main}, file ${BASH_SOURCE[1]:${BASH_SOURCE[0]}}, line $LINENO"; exit 1' ERR

# ===============================
# Directory Management
# ===============================
EPICS_HOST_ARCH="linux-x86_64"

# Root directory for EPICS installation
EPICS_ROOT="/epics"
EPICS_BASE="$EPICS_ROOT/base"
EPICS_EXTENSIONS="$EPICS_ROOT/extensions"
EPICS_MODULES="$EPICS_ROOT/modules"
# EDM_DIR="$EPICS_EXTENSIONS/src/edm"
EDM_DIR="$EPICS_ROOT/extensions/src/edm"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source /etc/os-release 
VERSION="$VERSION_ID" #detect ubuntu version
FILE_DIR_NAME="localFiles_$VERSION"

LOCAL_GIT_CACHE="$SCRIPT_DIR/localRepos" #enables offline downloads
LOCAL_DEB_REPO="$SCRIPT_DIR/$FILE_DIR_NAME" #targets relevant file package


#Ensure the script is run with sudo:
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires sudo privileges to work properly. Rerunning as sudo:"
    sudo bash "$0" "$@" --source-path "$SCRIPT_DIR" 

    exit 0 #exit original script after rerunning with sudo
fi

LOGFILE="$SCRIPT_DIR/logs.log"
exec > >(tee "$LOGFILE") 2>&1

# Ensure required directories exist
mkdir -p "$EPICS_ROOT"
mkdir -p "$EPICS_ROOT/configure"
mkdir -p "$EPICS_MODULES"
mkdir -p "$LOCAL_GIT_CACHE/src"


check_internet() { #check connectivity; used to install missing files in case of local corruption
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        return 0  # online
    else
        return 1  # offline
    fi
}

# -------------------------------
# Install OS Dependencies
# -------------------------------
#full package list:
# dpkg-dev make libpng-dev libmotif-dev libxm4 zlib1g-dev libgif-dev libx11-dev libxtst-dev libxmu-dev libdpkg-perl perl build-essential git vim

if true; then
    #if dir does not exist or is empty, create it & populate with .deb files
    if [ ! -d "$LOCAL_DEB_REPO" ] || [ -z "$(find "$LOCAL_DEB_REPO" -mindepth 1 -print -quit)" ]; then
        
        mkdir -p $LOCAL_DEB_REPO

        if check_internet; then #if internet is available, install packages
            echo "Local package repo for os $FILE_DIR_NAME not found, installing key packages from internet..."
            
            apt --fix-broken install -y #these may be unnecessary
            apt update

            apt-get -o=dir::cache::archives="$LOCAL_DEB_REPO" \
            install --download-only -y \
            dpkg-dev make libpng-dev libmotif-dev libxm4 zlib1g-dev libgif-dev libx11-dev libxtst-dev libxmu-dev libdpkg-perl perl build-essential git vim

            echo "Downloaded core files and dependencies"

        else #error message, exit if no internet
            echo "Error: local .deb repository not found or empty at $LOCAL_DEB_REPO"
            echo "Offline installation cannot proceed."
            exit 1
        fi
    fi


    #install from local repository
    if [ "$(ls -A "$LOCAL_DEB_REPO")" ]; then
        echo "Using local package repository: $LOCAL_DEB_REPO"

        #Prerequisite packages: dpkg-dev, make

        # --- Install make (needed to install dpkg-dev) ---
        if ! command -v make >/dev/null 2>&1; then
            echo "Installing make from local repo..."
            if ls "$LOCAL_DEB_REPO"/make_*.deb >/dev/null 2>&1; then
                dpkg -i "$LOCAL_DEB_REPO"/make_*.deb || true
                apt-get install -f -y || true
            else
                echo "Error: make_*.deb not found in $LOCAL_DEB_REPO"
                exit 1
            fi
        fi

        if true; then
            # --- Install dpkg-dev (needed later for dpkg -i) ---
            if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
                echo "Installing dpkg-dev from local repo..."
                if ls "$LOCAL_DEB_REPO"/dpkg-dev*.deb >/dev/null 2>&1; then
                    dpkg -i "$LOCAL_DEB_REPO"/dpkg-dev*.deb
                    # Fix unmet dependencies using local .debs
                    apt-get --fix-broken install -y -o Dir::Etc::sourcelist="-" \
                        -o Dir::Etc::sourceparts="-" \
                        -o APT::Get::Download-Only=false \
                        -o Dir::Etc::sourcelist="-" \
                        -o APT::Get::AllowUnauthenticated=true
                else
                    echo "Error: dpkg-dev*.deb not found in $LOCAL_DEB_REPO"
                    exit 1
                fi
            fi


        fi
                

        apt --fix-broken install -y

        # --- Point apt to the local .deb repository; install ---
        TMP_LIST=$(mktemp)
        echo "deb [trusted=yes] file:$LOCAL_DEB_REPO ./" | tee "$TMP_LIST" >/dev/null
        mv "$TMP_LIST" /etc/apt/sources.list.d/local.list

        cd "$LOCAL_DEB_REPO" || exit 1
        dpkg-scanpackages . /dev/null > Packages
        gzip -9c Packages > Packages.gz 

        apt update
        apt install -y \
        libpng-dev libmotif-dev libxm4 zlib1g-dev libgif-dev libx11-dev libxtst-dev libdpkg-perl\
        libxmu-dev perl build-essential git vim
    fi

    command -v git >/dev/null 2>&1 || { echo "git not found"; exit 1; } #validate git, make
    command -v make >/dev/null 2>&1 || { echo "make not found"; exit 1; }
fi

printf "Successfully installed dependencies"

# -------------------------------
# Clone EPICS Base
# -------------------------------
if true; then
    echo "Cloning EPICS Base..."
    cd "$EPICS_ROOT"

    if [ ! -d "$EPICS_BASE" ]; then #clone base.git
        if [ -d "$LOCAL_GIT_CACHE/base.git" ]; then
            echo "Cloning EPICS Base from local cache..."
            git clone --recursive "$LOCAL_GIT_CACHE/base.git" "$EPICS_BASE"
        else
            if check_internet; then
                echo "Local cache not found, cloning EPICS Base from GitHub..."
                git clone --recursive https://github.com/epics-base/epics-base "$EPICS_BASE"
            else
                echo "Error: Local cache empty and no internet connection. Cannot clone EPICS Base."
                exit 1
            fi
        fi
    fi


    if true; then #appends to calling user's bashrc, 
sudo -u "$SUDO_USER" tee -a "/home/$SUDO_USER/.bashrc" > /dev/null <<EOF
export EPICS_BASE="$EPICS_BASE"
export EPICS_EXTENSIONS="$EPICS_EXTENSIONS"
export EPICS_HOST_ARCH=linux-x86_64
export PATH="\$EPICS_BASE/bin/\$EPICS_HOST_ARCH:\$EPICS_EXTENSIONS/bin/\$EPICS_HOST_ARCH:\$PATH"
export EDMOBJECTS="\$EPICS_EXTENSIONS/src/edm/setup"
export EDMPVOBJECTS="\$EPICS_EXTENSIONS/src/edm/setup"
export EDMFILES="\$EPICS_EXTENSIONS/src/edm/setup"
export EDMHELPFILES="\$EPICS_EXTENSIONS/src/edm/helpFiles"
export EDMLIBS="\$EPICS_EXTENSIONS/lib/\$EPICS_HOST_ARCH"
export LD_LIBRARY_PATH="\$EPICS_BASE/lib/\$EPICS_HOST_ARCH:\${LD_LIBRARY_PATH:-}"
export EDM_USE_SHARED_LIBS=YES
EOF
    fi

    # -------------------------------
    # Build EPICS Base
    # -------------------------------
    echo "Building EPICS Base..."
    cd "$EPICS_BASE"
    make -j"$(nproc)"
fi

export EPICS_BASE="$EPICS_BASE" #adds paths to current shell (root: installer.sh)
export EPICS_EXTENSIONS="$EPICS_EXTENSIONS"
export EPICS_HOST_ARCH=linux-x86_64
export PATH="$EPICS_BASE/bin/$EPICS_HOST_ARCH:$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH:$PATH"
export EDMOBJECTS="$EPICS_EXTENSIONS/src/edm/setup"
export EDMPVOBJECTS="$EPICS_EXTENSIONS/src/edm/setup"
export EDMFILES="$EPICS_EXTENSIONS/src/edm/setup"
export EDMHELPFILES="$EPICS_EXTENSIONS/src/edm/helpFiles"
export EDMLIBS="$EPICS_EXTENSIONS/lib/$EPICS_HOST_ARCH"
export LD_LIBRARY_PATH="$EPICS_BASE/lib/$EPICS_HOST_ARCH:${LD_LIBRARY_PATH:-}"
export EDM_USE_SHARED_LIBS=YES

printf "Successfully installed EPICS base"

# -------------------------------
# Clone EPICS Extensions
# -------------------------------
echo "Cloning EPICS Extensions..."
cd "$EPICS_ROOT"

if [ ! -d "$EPICS_EXTENSIONS/.git" ]; then 
    if [ -d "$LOCAL_GIT_CACHE/extensions.git" ]; then
        echo "Cloning EPICS Extensions from local cache..."
        git clone --recursive "$LOCAL_GIT_CACHE/extensions.git" "$EPICS_EXTENSIONS"
    else
        echo "Cloning EPICS Extensions from GitHub..."
        git clone --recursive https://github.com/epics-extensions/extensions "$EPICS_EXTENSIONS"
    fi
fi

mkdir -p "$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH"
mkdir -p "$EPICS_EXTENSIONS/configure"

if ! grep -q '^EDM' "$EPICS_EXTENSIONS/configure/RELEASE" 2>/dev/null; then
    echo "EDM=\$(EPICS_EXTENSIONS)/src/edm" >> "$EPICS_EXTENSIONS/configure/RELEASE"
fi


if [ -e "$EPICS_ROOT/configure" ] && [ ! -L "$EPICS_ROOT/configure" ]; then #remove legacy '/epics/configure' dir if existing
    rm -rf "$EPICS_ROOT/configure"
fi

ln -s "$EPICS_BASE/configure" "$EPICS_ROOT/configure" #points /epics/configure to /epics/base/configure to 'fix' outdated pathing
echo "Created symlink: $EPICS_ROOT/configure -> $EPICS_BASE/configure"

echo "Successfully configured extensions!"



# -------------------------------
# Modify environment variables
# -------------------------------
if true; then
    ENV_SCRIPT="$EPICS_ROOT/epics_env.sh"

    # Create env script with system-wide exports
    cat > "$ENV_SCRIPT" <<'EOF'
export EPICS_ROOT=/epics
export EPICS_BASE=${EPICS_BASE:-/epics/base}
export EPICS_EXTENSIONS=${EPICS_EXTENSIONS:-$EPICS_ROOT/extensions}
export EPICS_HOST_ARCH=linux-x86_64
export PATH="${EPICS_BASE}/bin/${EPICS_HOST_ARCH}:$PATH"
export LD_LIBRARY_PATH="${EPICS_BASE}/lib/${EPICS_HOST_ARCH}:${LD_LIBRARY_PATH:-}"
EOF

    # Make readable by all users
    chmod 644 "$ENV_SCRIPT"

    # Link into global bashrc
    if ! grep -Fxq "source $ENV_SCRIPT" /etc/bash.bashrc; then
        echo "source $ENV_SCRIPT" | tee -a /etc/bash.bashrc >/dev/null
    fi
    
    if [ -f /epics/epics_env.sh ]; then #add to /etc/profile to add epics to SSH shell
        . /epics/epics_env.sh
    fi

    # Add to current user's bashrc as well
    if ! grep -Fxq "source $ENV_SCRIPT" ~/.bashrc; then
        echo "source $ENV_SCRIPT" >> ~/.bashrc
    fi

    printf "\n\nTo complete the installation: \nRun the command: source $EPICS_ROOT/epics_env.sh to add epics to your system environment"

    sudo -u "$SUDO_USER" bash -c "source \"$EPICS_ROOT/epics_env.sh\"" 
fi

echo "Done!"