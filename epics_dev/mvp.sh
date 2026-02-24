#!/usr/bin/env bash

#Jacob Mattie
#j_mattie@live.ca

#November, 2025

#this is charted to work only on Ubuntu 18.04, due to GUI dependencies on deprecated packages

debugFlag=$1 #Boolean for verbose outputs & breakpoints, passed as arg

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
FILES_DIR="$SCRIPT_DIR/installerFiles"

EPICS_ROOT="/opt/epics"
EPICS_BASE="$EPICS_ROOT/base"
EPICS_EXTENSIONS="$EPICS_ROOT/extensions"
EDM_DIR="$EPICS_EXTENSIONS/src/edm"
EPICS_GUI="$EPICS_ROOT/gui"

LOCAL_GIT_CACHE="$FILES_DIR/localRepos" #enables offline downloads
LOCAL_DEB_REPO="$FILES_DIR/$FILE_DIR_NAME"


LOGFILE="$SCRIPT_DIR/logs.log"
exec > >(tee "$LOGFILE") 2>&1

# Ensure required directories exist
mkdir -p "$EPICS_ROOT"

dependenciesList=( #used by apt install
    dpkg-dev make wine-stable
    build-essential git iperf3 nmap openssh-server vim libreadline-gplv2-dev libgif-dev libmotif-dev libxmu-dev
    libxmu-headers libxt-dev libxtst-dev xfonts-100dpi xfonts-75dpi x11proto-print-dev autoconf libtool sshpass
    )

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

breakpoint() {
    if [ "$debugFlag" = True ]; then
        local input=""
        printf "logged value(s): $@"
        printf "\npress 'enter' to continue\n"
        read input
    fi
}


cloneGitRepo() { #e.g. cloneGitRepo https://github[...]epics-base $EPICS_BASE "EPICS Base" "base"
    local githubLink="$1"
    local targetPath="$2"   # where it is to be cloned
    local dirName="$3"      # string name of repo (used for UI)
    local gitDirName="$4"   # name of repo as it is saved

    if [ ! -d "$targetPath" ]; then #if target path is empty
        #it may be worth adding a layer to validate the .git extension
        #sometimes .git dirs are cloned with/without the trailing .git tag
        #it's hardcoded here to look for .git dirs only. Edge case, but I'd bet it'll catch someone someday
        if [ -d "$LOCAL_GIT_CACHE/${gitDirName}.git" ]; then 
            echo "Cloning $dirName from local cache..."
            git clone --recursive "$LOCAL_GIT_CACHE/${gitDirName}.git" "$targetPath"
            return $? #most recent exit code; returns 0 on a success
        else
            if check_internet; then
                echo "Local cache not found. Cloning $irName from GitHub..."
                mkdir -p "$LOCAL_GIT_CACHE"
                git clone --recursive "$githubLink" "$LOCAL_GIT_CACHE/${gitDirName}.git" #ensures .git suffix
                git clone --recursive "$LOCAL_GIT_CACHE/${gitDirName}.git" "$targetPath"
                return $?
            fi
        fi

        echo "Error: Local cache empty and no internet connection. Cannot clone $dirName."
        exit 1
    fi
}
#endregion

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


#Detect/remove previous installations in $EPICS_ROOT
if [ -d $EPICS_ROOT ] && [ -n "$EPICS_ROOT" ]; then
    echo "Deleting previous epics install files"
    printf "Previous epics install detected at $EPICS_ROOT \nDeleting prior epics files.\n"
    rm -rf "$EPICS_ROOT"
fi


#detect WSL vs. native Linux (necessary for GUI)
if grep -qi microsoft /proc/version || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    sysEnv="WSL" 
else
    sysEnv="Native Ubuntu"
fi

printf "Linux framework detected: %s. Is this correct? [Y/n]:" "$sysEnv"
read response

response=${response,,}
if [[ "$response" == "n" || "$response" == "no" ]]; then
    if [[ "$sysEnv" == "WSL" ]]; then
        sysEnv="Native Ubuntu"
    else
        sysEnv="WSL"
    fi
fi

echo "Proceeding with installation"

#endregion

#endregion


# ---------------------------------------------------
# Install dependencies via apt/dpkg 
# ---------------------------------------------------

#region dependencies 
#if dir does not exist or is empty, create it & populate with .deb files
if [ ! -d "$LOCAL_DEB_REPO" ]; then 
    mkdir -p $LOCAL_DEB_REPO
    echo "Local deb repo not found. Creating..."
fi

        
missing_pkgs=()
for pkg in "${dependenciesList[@]}"; do #identify missing files for dependencies
    #NOTE: this only checks the top-level packages; their own dependencies are not handled here
    if ! ls "$LOCAL_DEB_REPO"/"$pkg"_*.deb >/dev/null 2>&1; then
        missing_pkgs+=("$pkg")  # add to list 
        printf "Missing package: %s" "$pkg"
    fi
done

if [ "${#missing_pkgs[@]}" -ne 0 ]; then 
    echo Missing package files.
    if check_internet; then #if internet is available, install packages
        echo "Internet available -- populating deb files"
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
            echo "Error: make_*.deb not found in $LOCAL_DEB_REPO"
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
            
    echo "Make, dpkg-dev installed. Beginning local installation"

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

#particular libxp files called for by epics-base
dpkg -i libxp6_1.0.2-1ubuntu1_amd64.deb libxp-dev_1.0.2-1ubuntu1_amd64.deb

echo "Successfully installed dependencies"


#endregion

# ---------------------------------------------------
# Validate, copy .git repositories 
# ---------------------------------------------------

#region git

#BASE
baseLink='https://github.com/epics-base/epics-base'
extensionsLink='https://github.com/epics-extensions/extensions'
edmLink='https://github.com/epicsdeb/edm.git'
guiLink='https://github.com/MattiasHenders/epics-gui-triumf.git'

cloneGitRepo $baseLink $EPICS_BASE "EPICS Base" "base"
cloneGitRepo $extensionsLink $EPICS_EXTENSIONS "EPICS Extensions" "extensions"
cloneGitRepo $edmLink $EDM_DIR "EDM" "edm"
cloneGitRepo $guiLink $EPICS_GUI "EPICS GUI" "epics-gui-triumf"

#region deprecated git clones
#if [ ! -d "$EPICS_BASE" ]; then #clone base.git
    #if [ -d "$LOCAL_GIT_CACHE/base.git" ]; then
        #echo "Cloning EPICS Base from local cache..."
        #git clone --recursive "$LOCAL_GIT_CACHE/base.git" "$EPICS_BASE" 
    #else
        #if check_internet; then
            #echo "Local cache not found, cloning EPICS Base from GitHub..."
            #git clone --recursive https://github.com/epics-base/epics-base "$LOCAL_GIT_CACHE"
            #git clone --recursive "$LOCAL_GIT_CACHE/base.git" "$EPICS_BASE"
        #else
            #echo "Error: Local cache empty and no internet connection. Cannot clone EPICS Base."
            #exit 1
        #fi
    #fi
#fi

##EXTENSIONS
#if [ ! -d "$EPICS_EXTENSIONS/.git" ]; then 
    #if [ -d "$LOCAL_GIT_CACHE/extensions.git" ]; then
        #echo "Cloning EPICS Extensions from local cache..."
        #git clone --recursive "$LOCAL_GIT_CACHE/extensions.git" "$EPICS_EXTENSIONS"
    #else
        #if check_internet; then
            #echo "Cloning EPICS Extensions from GitHub..."
            #git clone --recursive https://github.com/epics-extensions/extensions "$LOCAL_GIT_CACHE"
            #git clone --recursive "$LOCAL_GIT_CACHE/extensions.git" "$EPICS_EXTENSIONS"
        #else
            #echo "Error: Local cache empty and no internet connection. Cannot clone EPICS Extensions."
            #exit 1
    #fi
#fi

##EDM
#if [ ! -d "$EDM_DIR/.git" ]; then 
    #if [ -d "$LOCAL_GIT_CACHE/edm.git" ]; then
        #echo "Cloning EPICS GUI from local cache..."
        #git clone --recursive "$LOCAL_GIT_CACHE/edm.git" "$EPICS_GUI"
    #else
        #if check_internet; then
            #echo "Cloning EDM from GitHub..."
            #git clone --recursive https://github.com/epicsdeb/edm.git "$LOCAL_GIT_CACHE"
            #git clone --recursive "$LOCAL_GIT_CACHE/edm.git" "$EPICS_GUI"
        #else
            #echo "Error: Local cache empty and no internet connection. Cannot clone EDM."
            #exit 1
    #fi
#fi

##EPICS GUI
#if [ ! -d "$EPICS_GUI/.git" ]; then 
    #if [ -d "$LOCAL_GIT_CACHE/epics-gui-triumf.git" ]; then
        #echo "Cloning EPICS GUI from local cache..."
        #git clone --recursive "$LOCAL_GIT_CACHE/epics-gui-triumf.git" "$EPICS_GUI"
    #else
        #if check_internet; then
            #echo "Cloning EPICS GUI from GitHub..."
            #git clone --recursive https://github.com/MattiasHenders/epics-gui-triumf.git "$LOCAL_GIT_CACHE"
            #git clone --recursive "$LOCAL_GIT_CACHE/epics-gui-triumf.git" "$EPICS_GUI"
        #else
            #echo "Error: Local cache empty and no internet connection. Cannot clone EPICS GUI."
            #exit 1
    #fi
#fi
#endregion

#endregion


# ---------------------------------------------------
# Prepare ExtensionsTop
# ---------------------------------------------------

tar xvzf $FILES_DIR/extensionsTop_20120904.tar.gz -C $EPICS_ROOT #creates extensions dir

# ---------------------------------------------------
# Build EPICS Base
# ---------------------------------------------------

#region epicsBase

#adds paths to current shell (root: installer.sh)
export EPICS_BASE="$EPICS_BASE" 
export EPICS_EXTENSIONS="$EPICS_EXTENSIONS"
export EPICS_HOST_ARCH="$EPICS_HOST_ARCH"

export PATH="$EPICS_BASE/bin/$EPICS_HOST_ARCH:$PATH"
export PATH="$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH:$PATH"

export EPICS_CA_AUTO_ADDR_LIST=YES

export EDMPVOBJECTS="$EPICS_EXTENSIONS/src/edm/setup"
export EDMOBJECTS="$EPICS_EXTENSIONS/src/edm/setup"
export EDMHELPFILES="$EPICS_EXTENSIONS/src/edm/helpFiles"
export EDMFILES="$EPICS_EXTENSIONS/src/edm/edmMain"
export EDMLIBS="$EPICS_EXTENSIONS/lib/$EPICS_HOST_ARCH"

export LD_LIBRARY_PATH="$EDMLIBS:$EPICS_BASE/lib/$EPICS_HOST_ARCH"


echo "Starting EPICS Base make"
make -j"$(nproc)" -C "$EPICS_BASE"

echo "Successfully installed EPICS base"


#add paths to calling user's shell (user invoking sudo)

#check for presence of $EPICS_MARKER in bashrc before appending
#if marker is present, then skip. This avoids duplicates

EPICS_MARKER="#=======  EPICS ENVIRONMENT VARIABLES ======= "
if ! grep -qF "$EPICS_MARKER" "/home/$SUDO_USER/.bashrc"; then 
    sudo -u "$SUDO_USER" tee -a "/home/$SUDO_USER/.bashrc" > /dev/null <<EOF

$EPICS_MARKER
export EPICS_BASE="$EPICS_BASE"
export EPICS_EXTENSIONS="$EPICS_EXTENSIONS"
export EPICS_GUI="$EPICS_GUI"
export EPICS_HOST_ARCH=$EPICS_HOST_ARCH

export PATH="$EPICS_BASE/bin/$EPICS_HOST_ARCH:\$PATH"
export PATH="$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH:\$PATH"

export EPICS_CA_AUTO_ADDR_LIST=YES

export EDMOBJECTS="$EPICS_EXTENSIONS/src/edm/setup"
export EDMPVOBJECTS="$EPICS_EXTENSIONS/src/edm/setup"
export EDMFILES="$EPICS_EXTENSIONS/src/edm/setup"
export EDMHELPFILES="$EPICS_EXTENSIONS/src/edm/helpFiles"
export EDMLIBS="$EPICS_EXTENSIONS/lib/$EPICS_HOST_ARCH"
export EDM_USE_SHARED_LIBS=YES

export LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
source $EDM_DIR/setup/setup.sh 

EOF

fi

echo "Succesfully configured EPICS Base"

#endregion


# ---------------------------------------------------
# Install EPICS Extensions -- deprecated
# ---------------------------------------------------

#region epics extensions - deprecated
#cd "$EPICS_ROOT"
#
#mkdir -p "$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH"
#mkdir -p "$EPICS_EXTENSIONS/configure"
#
#if ! grep -q '^EDM' "$EPICS_EXTENSIONS/configure/RELEASE" 2>/dev/null; then
#    echo "EDM=\$(EPICS_EXTENSIONS)/src/edm" >> "$EPICS_EXTENSIONS/configure/RELEASE"
#fi
#
#
#if [ -e "$EPICS_ROOT/configure" ] && [ ! -L "$EPICS_ROOT/configure" ]; then #remove legacy '/epics/configure' dir if existing
#    rm -rf "$EPICS_ROOT/configure"
#fi
#
#
#if [ ! -e "$EPICS_ROOT/configure" ]; then
#    ln -s "$EPICS_BASE/configure" "$EPICS_ROOT/configure" #points /epics/configure to /epics/base/configure to 'fix' outdated pathing
#fi
#
#
#echo "Created symlink: $EPICS_ROOT/configure -> $EPICS_BASE/configure"
#
#echo "Successfully configured extensions!"

#endregion


# ---------------------------------------------------
# Clone EDM into Extensions
# ---------------------------------------------------

#region EDM 

cd $EPICS_ROOT #relative paths >:(

sed -i -e "21cEPICS_BASE=$EPICS_BASE" -e '25s/^/#/' extensions/configure/RELEASE
sed -i -e '14cX11_LIB=/usr/lib/x86_64-linux-gnu' -e '18cMOTIF_LIB=/usr/lib/x86_64-linux-gnu' extensions/configure/os/CONFIG_SITE.linux-x86_64.linux-x86_64

#cp -r $LOCAL_GIT_CACHE/edm .
#cd "$EPICS_EXTENSIONS/src"
cd $EDM_DIR
#these few lines sketch me out. Too much relative pathing invites errors

sed -i -e '15s/$/ -DGIFLIB_MAJOR=5 -DGIFLIB_MINOR=1/' giflib/Makefile
sed -i -e 's| ungif||g' giflib/Makefile*

echo "Making edm"
make clean
make
echo "Successfully made edm"

cd setup

sed -i -e '53cfor libdir in baselib lib epicsPv locPv calcPv util choiceButton pnglib diamondlib giflib videowidget' setup.sh
sed -i -e '79d' setup.sh
sed -i -e '81i\ \ \ \ $EDM -add $EDMBASE/pnglib/O.$ODIR/lib57d79238-2924-420b-ba67-dfbecdf03fcd.so' setup.sh
sed -i -e '82i\ \ \ \ $EDM -add $EDMBASE/diamondlib/O.$ODIR/libEdmDiamond.so' setup.sh
sed -i -e '83i\ \ \ \ $EDM -add $EDMBASE/giflib/O.$ODIR/libcf322683-513e-4570-a44b-7cdd7cae0de5.so' setup.sh
sed -i -e '84i\ \ \ \ $EDM -add $EDMBASE/videowidget/O.$ODIR/libTwoDProfileMonitor.so' setup.sh
HOST_ARCH=$EPICS_HOST_ARCH sh setup.sh

echo "Successfully installed & configured EDM"

#endregion

#region edm spaghetti -- deprecated
#if [ -d "localRepos/edm" ]; then 
#    mkdir -p $EPICS_EXTENSIONS/src #/epics/base/extensions/src
#    cp -r localRepos/edm/* $EPICS_EXTENSIONS/src
#
#    sudo find $EPICS_ROOT -type f -name Makefile -exec sed -i 's|\$top/configure|\$top/base/configure|g' {} +
#    sudo find "$EPICS_ROOT" -type f -name Makefile -exec sed -i "s|^TOP = [./]\+|TOP = $EPICS_ROOT|" {} + #replace any combination of . / with absolute path
#
#
#    #Edits config files 
#    sed -i 's|^EPICS_BASE=$(TOP)/\.\./base|EPICS_BASE=$(TOP)|' /epics/extensions/configure/RELEASE
#    sed -i -e 's| ungif||g' "$EPICS_EXTENSIONS/src/giflib/Makefile"
#
#    # edits all files in /epics:
#    #   /epics/configure ---> /epics/base/configure
#
#    cd "$EPICS_EXTENSIONS/src"
#
#    echo "Preparing to make EDM"
#
#    #edit Makefile in /epics/extensions/src: 
#    #change:
#    #   include $(TOP)/configure/CONFIG
#    # to 
#    #   include $(TOP)/base/configure/CONFIG
#    # sed -i 's|$(TOP)/configure/CONFIG|$(TOP)/base/configure/CONFIG|' /epics/extensions/src/Makefile
#
#    make -j"$(nproc)"
#fi

#endregion


# ---------------------------------------------------
# Modify environment variables -- deprecated
# ---------------------------------------------------

#region environment variables -- deprecated
#ENV_SCRIPT="$EPICS_ROOT/epics_env.sh" #This should be redundant; the installer adds to path directly
##however, should it be needed, this adds paths manually
#
#cat > "$ENV_SCRIPT" <<EOF
#
#export PATH="$EPICS_BASE/bin/$EPICS_HOST_ARCH:$PATH"
#export PATH="$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH:$PATH"
#
#export EPICS_ROOT=$EPICS_ROOT
#export EPICS_BASE=$EPICS_BASE
#export EPICS_GUI="$EPICS_GUI"
#export EPICS_EXTENSIONS=$EPICS_EXTENSIONS
#
#export EPICS_HOST_ARCH=$EPICS_HOST_ARCH
#
#export LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
#export EPICS_CA_AUTO_ADDR_LIST=YES
#
#export EDMOBJECTS="$EPICS_EXTENSIONS/src/edm/setup"
#export EDMPVOBJECTS="$EPICS_EXTENSIONS/src/edm/setup"
#export EDMFILES="$EPICS_EXTENSIONS/src/edm/setup"
#export EDMHELPFILES="$EPICS_EXTENSIONS/src/edm/helpFiles"
#export EDMLIBS="$EPICS_EXTENSIONS/lib/$EPICS_HOST_ARCH"
#export EDM_USE_SHARED_LIBS=YES
#
#EOF
#
## Make readable by all users
#chmod 644 "$ENV_SCRIPT"

#sudo -u "$SUDO_USER" bash -c "source \"$EPICS_ROOT/epics_env.sh\""  #adds ENV_SCRIPT to active shell immediately

#endregion

# ---------------------------------------------------
# GUI -- Xming, for WSL instances 
# ---------------------------------------------------

echo "Skipping XMING install"

# ---------------------------------------------------
# End-script processes 
# ---------------------------------------------------

echo "Done!"
