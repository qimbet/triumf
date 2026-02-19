#!/usr/bin/env bash

#Jacob Mattie
#j_mattie@live.ca

#November, 2025

#this is charted to work only on Ubuntu 18.04, due to GUI dependencies on deprecated packages

debugFlag=$1 #Boolean for verbose outputs & breakpoints, passed as arg
breakpointLevel=0 #breakpoints are numbered, this sets the depth that the program will run

set -euo pipefail

trap 'echo "ERROR in function ${FUNCNAME[0]:-main}, file ${BASH_SOURCE[1]:${BASH_SOURCE[0]}}, line $LINENO"; exit 1' ERR

# ===================================================
# Directory Management
# ===================================================

#region paths, constants, functions
source /etc/os-release  #add $VERSION_ID to shell
FILE_DIR_NAME="localFiles_$VERSION_ID"
EPICS_HOST_ARCH="linux-x86_64"

# Root directory for EPICS installation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EPICS_ROOT="/opt/epics"
EPICS_BASE="$EPICS_ROOT/base"
EPICS_EXTENSIONS="$EPICS_ROOT/extensions"
EDM_DIR="$EPICS_ROOT/extensions/src/edm"

LOCAL_GIT_CACHE="$SCRIPT_DIR/localRepos" #enables offline downloads
LOCAL_DEB_REPO="$SCRIPT_DIR/$FILE_DIR_NAME"


LOGFILE="$SCRIPT_DIR/logs.log"
exec > >(tee "$LOGFILE") 2>&1

# Ensure required directories exist
mkdir -p "$EPICS_ROOT"
mkdir -p "$EPICS_ROOT/configure"


dependenciesList=( #used by apt install
    dpkg-dev make
    build-essential git iperf3 nmap openssh-server vim libreadline-gplv2-dev libgif-dev libmotif-dev libxmu-dev
    libxmu-headers libxt-dev libxtst-dev xfonts-100dpi xfonts-75dpi x11proto-print-dev autoconf libtool sshpass
    )


#region user interaction; runtime environment / permissions
    #ensure the os is the right version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$NAME" != "Ubuntu" ] || [ "$VERSION_ID" != "18.04" ]; then
            echo "The installer requires os version: *** Ubuntu 18.04 *** "
            echo "EPICS will install properly, but the GUI will not work. Continue? [Y/n]" #edit for accuracy after release!!

            ans=${answer:-Y}
            if [[ "$ans" =~ ^[Yy]$ ]]; then 
                :
            else
                echo "Quitting"
                exit 1
            fi

        fi
    fi

    #Ensure the script is run with sudo:
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script requires sudo privileges to work properly. Rerunning as sudo:"
        sudo bash "$0" "$@" --source-path "$SCRIPT_DIR" 

        exit 0 #exit original script after rerunning with sudo
    fi

#endregion


#region functions
check_internet() { #check connectivity; used to install missing files in case of local corruption
    if [ "$debugFlag" = True ]; then
        printf "Local files missing!\nPress enter to continue"
        read input
    fi
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        return 1  # online
    else
        return 0  # offline
    fi
}

debug() {
    if [ "$debugFlag" = True ]; then
        local input=""
        printf "logged value(s): $@"
        printf "\npress 'enter' to continue\n"
        read input
    fi
}

breakpoint() {
    local num=$1
    if [ "$breakpointLevel" -ge "$num" ]; then
        debug "Breakpoint reached; $num"
    fi
}
#endregion

#endregion


# ---------------------------------------------------
# Install dependencies via apt/dpkg 
# ---------------------------------------------------

#region dependencies 
#if dir does not exist or is empty, create it & populate with .deb files
if [ ! -d "$LOCAL_DEB_REPO" ]; then 
    mkdir -p $LOCAL_DEB_REPO
    debug "Local deb repo not found. Creating..."
fi

        
for pkg in "${dependenciesList[@]}"; do #identify missing files for dependencies
    #NOTE: this only checks the top-level packages; their own dependencies are not handled here
    if ! ls "$LOCAL_DEB_REPO"/"$pkg"_*.deb >/dev/null 2>&1; then
        missing_pkgs+=("$pkg")  # add to list 
    fi
done

if [ "${#missing_pkgs[@]}" -ne 0 ]; then 
    if check_internet; then #if internet is available, install packages
        debug "Internet available -- populating deb files"
        echo "Local package repo for os $FILE_DIR_NAME not found, installing key packages from internet..."

        apt-get -o=dir::cache::archives="$LOCAL_DEB_REPO" install --download-only -y "${dependenciesList[@]}" #download .deb files to localDir

        echo "Downloaded core files and dependencies"

    else #error message, exit if no internet
        echo "Error: local .deb repository not found or empty at $LOCAL_DEB_REPO"
        echo "No internet access: installation cannot proceed."
        exit 1
    fi
fi


#install from local repository
if [ "$(ls -A "$LOCAL_DEB_REPO")" ]; then

    #region prerequisite installs; make, dpkg-dev
    # Install make (needed to install dpkg-dev)
    if ! command -v make >/dev/null 2>&1; then #if make does not exist in $PATH
        echo "Installing make from local repo..."

        if ls "$LOCAL_DEB_REPO"/make_*.deb >/dev/null 2>&1; then
            dpkg -i "$LOCAL_DEB_REPO"/make_*.deb #attempt to install make 

            # Fix unmet dependencies using local .debs
            apt-get --fix-broken install -y -o Dir::Etc::sourcelist="-" \
                -o Dir::Etc::sourceparts="-" \
                -o APT::Get::Download-Only=false \
                -o Dir::Etc::sourcelist="-" \
                -o APT::Get::AllowUnauthenticated=true
        else
            debug "Error: make_*.deb not found in $LOCAL_DEB_REPO"
            exit 1
        fi
    fi

    if ! command -v dpkg-scanpackages >/dev/null 2>&1; then #if dpkg does not exist in $PATH
        #use make to install dpkg-dev
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
    #endregion
            
    debug "Make, dpkg-dev installed. Beginning local installation"

    #install dependenciesList from local_deb_repo 
    TMP_LIST=$(mktemp)
    echo "deb [trusted=yes] file:$LOCAL_DEB_REPO ./" | tee "$TMP_LIST" >/dev/null
    mv "$TMP_LIST" /etc/apt/sources.list.d/local.list #apt fileSources directory

    cd "$LOCAL_DEB_REPO" || exit 1
    dpkg-scanpackages . /dev/null > Packages #indexes files
    gzip -9c Packages > Packages.gz 

    apt update #update cache
    apt install -y "${dependenciesList[@]}"
fi

command -v git >/dev/null 2>&1 || { echo "git not found"; exit 1; } #validate git, make
command -v make >/dev/null 2>&1 || { echo "make not found"; exit 1; }

echo "Successfully installed dependencies"


#endregion

# ---------------------------------------------------
# Install EPICS Base
# ---------------------------------------------------

#region epicsBase
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

# ---------------------------------------------------
# Build EPICS Base
# ---------------------------------------------------
echo "Building EPICS Base..."
cd "$EPICS_BASE"
debug "Starting EPICS Base make"
make -j"$(nproc)"

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

echo "Successfully installed EPICS base"

#endregion


# ---------------------------------------------------
# Install EPICS Extensions
# ---------------------------------------------------

#region epics extensions

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


if [ ! -e "$EPICS_ROOT/configure" ]; then
    ln -s "$EPICS_BASE/configure" "$EPICS_ROOT/configure" #points /epics/configure to /epics/base/configure to 'fix' outdated pathing
fi


echo "Created symlink: $EPICS_ROOT/configure -> $EPICS_BASE/configure"

echo "Successfully configured extensions!"

#endregion


# ---------------------------------------------------
# Clone EDM into Extensions
# ---------------------------------------------------

#region EDM

cd $EPICS_ROOT


sed -i -e '21cEPICS_BASE=/opt/epics/epics-base' -e '25s/^/#/' extensions/configure/RELEASE
sed -i -e '14cX11_LIB=/usr/lib/x86_64-linux-gnu' -e '18cMOTIF_LIB=/usr/lib/x86_64-linux-gnu' extensions/configure/os/CONFIG_SITE.linux-x86_64.linux-x86_64

cd "$EPICS_ROOT/extensions/src"
cp -r $LOCAL_GIT_CACHE/edm .
cd "$EPICS_ROOT/extensions/src"

sed -i -e '15s/$/ -DGIFLIB_MAJOR=5 -DGIFLIB_MINOR=1/' edm/giflib/Makefile
sed -i -e 's| ungif||g' edm/giflib/Makefile*

cd edm
make clean
make
cd setup
sed -i -e '53cfor libdir in baselib lib epicsPv locPv calcPv util choiceButton pnglib diamondlib giflib
videowidget' setup.sh
sed -i -e '79d' setup.sh
sed -i -e '81i\ \ \ \ $EDM -add $EDMBASE/pnglib/O.$ODIR/lib57d79238-2924-420b-ba67-dfbecdf03fcd.so' setup.sh
sed -i -e '82i\ \ \ \ $EDM -add $EDMBASE/diamondlib/O.$ODIR/libEdmDiamond.so' setup.sh
sed -i -e '83i\ \ \ \ $EDM -add $EDMBASE/giflib/O.$ODIR/libcf322683-513e-4570-a44b-7cdd7cae0de5.so' setup.sh
sed -i -e '84i\ \ \ \ $EDM -add $EDMBASE/videowidget/O.$ODIR/libTwoDProfileMonitor.so' setup.sh
HOST_ARCH=linux-x86_64 sh setup.sh



if [ -d "localRepos/edm" ]; then 
    mkdir -p $EPICS_EXTENSIONS/src #/epics/base/extensions/src
    cp -r localRepos/edm/* $EPICS_EXTENSIONS/src

    sudo find $EPICS_ROOT -type f -name Makefile -exec sed -i 's|\$top/configure|\$top/base/configure|g' {} +
    sudo find "$EPICS_ROOT" -type f -name Makefile -exec sed -i "s|^TOP = [./]\+|TOP = $EPICS_ROOT|" {} + #replace any combination of . / with absolute path


    #Edits config files 
    sed -i 's|^EPICS_BASE=$(TOP)/\.\./base|EPICS_BASE=$(TOP)|' /epics/extensions/configure/RELEASE
    sed -i -e 's| ungif||g' "$EPICS_EXTENSIONS/src/giflib/Makefile"

    # edits all files in /epics:
    #   /epics/configure ---> /epics/base/configure

    cd "$EPICS_EXTENSIONS/src"

    echo "Preparing to make EDM"

    #edit Makefile in /epics/extensions/src: 
    #change:
    #   include $(TOP)/configure/CONFIG
    # to 
    #   include $(TOP)/base/configure/CONFIG
    # sed -i 's|$(TOP)/configure/CONFIG|$(TOP)/base/configure/CONFIG|' /epics/extensions/src/Makefile

    make -j"$(nproc)"
fi

#endregion


# ---------------------------------------------------
# Modify environment variables
# ---------------------------------------------------

#region environment variables
if true; then
    ENV_SCRIPT="$EPICS_ROOT/epics_env.sh"

    # Create env script with system-wide exports
    cat > "$ENV_SCRIPT" <<'EOF'
export EPICS_ROOT=/opt/epics
export EPICS_BASE=${EPICS_BASE:-$EPICS_ROOT/base}
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

    # printf "\n\nRun the command: source $EPICS_ROOT/epics_env.sh to add epics to your system environment"

    sudo -u "$SUDO_USER" bash -c "source \"$EPICS_ROOT/epics_env.sh\""  #adds ENV_SCRIPT to active shell immediately
fi

#endregion


# ---------------------------------------------------
# End-script processes 
# ---------------------------------------------------

echo "Done!"
