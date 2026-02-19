#!/usr/bin/env bash


#Jacob Mattie
#j_mattie@live.ca

#November, 2025



set -euo pipefail

# ===============================
# Directory Management
# ===============================
EPICS_HOST_ARCH="linux-x86_64"

# Root directory for EPICS installation
EPICS_ROOT="/epics"
EPICS_BASE="$EPICS_ROOT/base"
EPICS_EXTENSIONS="$EPICS_ROOT/extensions"
EPICS_MODULES="$EPICS_ROOT/modules"
EDM_DIR="$EPICS_EXTENSIONS/src/edm"


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_GIT_CACHE="$SCRIPT_DIR/localRepos" #enables offline downloads
LOCAL_DEB_REPO="$SCRIPT_DIR/localFiles"

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


check_internet() { #backup in case local files are unavailable
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        return 0  # online
    else
        return 1  # offline
    fi
}

set_epics_env() {
  export EPICS_ROOT="/epics"
  export EPICS_BASE="$EPICS_ROOT/base"
  export EPICS_EXTENSIONS="$EPICS_ROOT/extensions"
  export EPICS_HOST_ARCH="linux-x86_64"
  export PATH="$EPICS_BASE/bin/$EPICS_HOST_ARCH:$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH:$PATH"
  export LD_LIBRARY_PATH="$EPICS_BASE/lib/$EPICS_HOST_ARCH:${LD_LIBRARY_PATH:-}"
  export EDM_USE_SHARED_LIBS=YES
}
set_epics_env

# -------------------------------
# Install OS Dependencies
# -------------------------------
#full package list:
# dpkg-dev make libpng-dev libmotif-dev libxm4 zlib1g-dev libgif-dev libx11-dev libxtst-dev libxmu-dev perl build-essential git vim

#ensure dpkg-dev is installed
if [ -d "$LOCAL_DEB_REPO" ] && ls "$LOCAL_DEB_REPO"/dpkg-dev*.deb >/dev/null 2>&1; then
    echo "Bootstrapping dpkg-dev from local repo..."
    dpkg -i "$LOCAL_DEB_REPO"/dpkg-dev*.deb || true
    # Fix dependencies that may be missing
    apt-get install -f -y || true
fi

if [ -d "$LOCAL_DEB_REPO" ] && [ "$(ls -A "$LOCAL_DEB_REPO")" ]; then
    echo "Using local package repository: $LOCAL_DEB_REPO"

    # --- Step 0: Bootstrap make and dpkg-dev if missing ---
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

    # --- Step 1: Ensure dpkg-dev is installed ---
    if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
        echo "Installing dpkg-dev from local repo (required for index generation)..."
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

    # --- Step 2: Register the local repo ---
    TMP_LIST=$(mktemp)
    echo "deb [trusted=yes] file:$LOCAL_DEB_REPO ./" | tee "$TMP_LIST" >/dev/null
    mv "$TMP_LIST" /etc/apt/sources.list.d/local.list

    cd "$LOCAL_DEB_REPO" || exit 1
    dpkg-scanpackages . /dev/null > Packages
    gzip -9c Packages > Packages.gz 

    apt update
    apt install -y \
    libpng-dev libmotif-dev libxm4 zlib1g-dev libgif-dev libx11-dev libxtst-dev \
    libxmu-dev perl build-essential git vim

elif check_internet; then
    echo "Local package repo not found, falling back to online installation..."
    apt --fix-broken install -y
    apt update
    apt install -y \
    libpng-dev libmotif-dev libxm4 zlib1g-dev libgif-dev libx11-dev libxtst-dev \
    libxmu-dev perl build-essential git vim make dpkg-dev

else
    echo "Error: local .deb repository not found or empty at $LOCAL_DEB_REPO"
    echo "Offline installation cannot proceed."
    exit 1
fi

ldconfig

command -v git >/dev/null 2>&1 || { echo "git not found"; exit 1; } #validate installs of git, make
command -v make >/dev/null 2>&1 || { echo "make not found"; exit 1; }

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

    # -------------------------------
    # Set Environment Variables
    # -------------------------------
    if true; then
        export EPICS_BASE="$EPICS_BASE"
        export EPICS_EXTENSIONS="$EPICS_EXTENSIONS"
        export EPICS_HOST_ARCH=linux-x86_64
        export PATH="$EPICS_BASE/bin/$EPICS_HOST_ARCH:$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH:$PATH"

        # Required for EDM
        export EDMOBJECTS="$EPICS_EXTENSIONS/src/edm/setup"
        export EDMPVOBJECTS="$EPICS_EXTENSIONS/src/edm/setup"
        export EDMFILES="$EPICS_EXTENSIONS/src/edm/setup"
        export EDMHELPFILES="$EPICS_EXTENSIONS/src/edm/helpFiles"
        export EDMLIBS="$EPICS_EXTENSIONS/lib/$EPICS_HOST_ARCH"
    fi

    # -------------------------------
    # Build EPICS Base
    # -------------------------------
    echo "Building EPICS Base..."
    cd "$EPICS_BASE"
    make -j"$(nproc)"
fi


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

# # -------------------------------
# # Clone EDM into Extensions
# # -------------------------------
# echo "Cloning EDM..."
# mkdir -p "$(dirname "$EDM_DIR")"  # ensure src/ exists

# if [ ! -d "$EDM_DIR" ]; then
#     if [ -d "$LOCAL_GIT_CACHE/edm.git" ]; then
#         echo "Cloning EDM from local cache..."
#         git clone --recursive "$LOCAL_GIT_CACHE/edm.git" "$EDM_DIR"
#     else
#         if check_internet; then
#             echo "Local cache empty, cloning EDM from GitHub..."
#             git clone --recursive https://github.com/epicsdeb/edm "$EDM_DIR"
#         else
#             echo "Error: Local cache empty and no internet connection. Cannot clone EDM."
#             exit 1
#         fi
#     fi
# fi

# mkdir -p "$EPICS_EXTENSIONS/lib/linux-x86_64"S


# if [ true ]; then
#     # -------------------------------
#     # Patch CONFIG_SITE for EDM
#     # -------------------------------

#     CONFIG_SITE="$EPICS_EXTENSIONS/configure/os/CONFIG_SITE.$EPICS_HOST_ARCH"
#     mkdir -p "$(dirname "$CONFIG_SITE")"

#     cat > "$CONFIG_SITE" <<EOF
# EDM_USE_SHARED_LIBS=YES
# X11_LIB=/usr/lib/x86_64-linux-gnu
# X11_INC=/usr/include
# MOTIF_LIB=/usr/lib/x86_64-linux-gnu
# MOTIF_INC=/usr/include
# EOF


#     export CONFIG_SITE

#     # -------------------------------
#     # Build EDM
#     # -------------------------------

#     echo "Building EDM..."
#     cd "$EDM_DIR"
#     make clean
#     make -j"$(nproc)"

#     echo "EDM build process completed"


#     # Install EDM binary
#     mkdir -p "$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH"

#     EDM_BIN="$(find "$EDM_DIR" -type f -executable -name edm -print -quit)"
#     [ -n "$EDM_BIN" ] || { echo "edm binary not found"; exit 1; }
#     install -m 755 "$EDM_BIN" "$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH/"


#     # -------------------------------
#     # Patch EDM Fonts
#     # -------------------------------
#     EDM_FONTS="$EDM_DIR/setup/fonts.list"
#     echo "Configuring EDM fonts..."
#     mkdir -p "$(dirname "$EDM_FONTS")"  # ensure setup/ exists

#     cat > "$EDM_FONTS" <<'EOF'
# courier-bold-r-12.0
# helvetica-bold-r-12.0
# courier={
#     -misc-liberation mono-(medium,bold)-(r,i)-normal--0-(80=90,100,120,140,160,180,200,240,280,320,360,420,480,600,720)-75-75-m-0-*-* exact
#     -adobe-courier-(medium,bold)-(r,o)-normal--0-(80,100,120,140,160,180,200,240,280,320,360,420,480,600,720)-75-75-*-0-*-1
#     -monotype-arial-(medium,bold)-(r,i)-normal--*-(80,100,120,140,160,180,200,240,280,320,360,420,480,600,720)-75-75-p-*-*-*
# }
# EOF


#     # -------------------------------
#     # UI
#     # -------------------------------
#     echo "EPICS + EDM installation complete!"
#     echo "Remember to source the environment variables before running EPICS or EDM:"
#     echo "  source $EPICS_ROOT/epics_env.sh"
# fi

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

    source "$ENV_SCRIPT" #adds ENV_SCRIPT to active shell immediately
fi

