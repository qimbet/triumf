#!/usr/bin/env bash

#Jacob Mattie
#j_mattie@live.ca

#November, 2025

#this is charted to work only on Ubuntu 18.04, due to GUI dependencies on deprecated packages

debugFlag=$1 #Boolean for verbose outputs & breakpoints, passed as arg
debugFlag="True"

set -euo pipefail

trap 'echo "ERROR in function ${FUNCNAME[0]:-main}, file ${BASH_SOURCE[1]:${BASH_SOURCE[0]}}, line $LINENO"; exit 1' ERR
caller="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"

breakerStr="*******************************************"

# ===================================================
# Directory Management
# ===================================================

#region paths, constants, functions
source /etc/os-release  #add $VERSION_ID to shell
FILE_DIR_NAME="localFiles_$VERSION_ID"
PACKAGES_ZIP="packages_$VERSION_ID.zip"
EPICS_HOST_ARCH="linux-x86_64"

# Root directory for EPICS installation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$SCRIPT_DIR/installerFiles"
DEPENDENCIES_DIR="$FILES_DIR/dependencies"

EPICS_ROOT="/opt/epics"
EPICS_BASE="$EPICS_ROOT/base"
EPICS_EXTENSIONS="$EPICS_ROOT/extensions"
EDM_DIR="$EPICS_EXTENSIONS/src/edm"
EPICS_GUI="$EPICS_ROOT/gui"

EDMBASE="$EPICS_EXTENSIONS/src/edm" #no underscore as this is imported from EDM installation script

FONTS_DIR="$EPICS_GUI/fonts"

LOCAL_GIT_CACHE="$FILES_DIR/localRepos" #enables offline downloads
LOCAL_DEB_REPO="$FILES_DIR/$FILE_DIR_NAME"


LOGFILE="$SCRIPT_DIR/logs.log"
exec > >(tee "$LOGFILE") 2>&1

dependenciesList=( #used by apt install
    dpkg-dev make wine-stable 
    build-essential git iperf3 nmap openssh-server vim libreadline-gplv2-dev libgif-dev libmotif-dev libxmu-dev
    libxmu-headers libxt-dev libxtst-dev xfonts-100dpi xfonts-75dpi gsfonts-x11 x11proto-print-dev autoconf libtool sshpass
    libfont-ttf-perl
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
            printf "Successfullly cloned repository: %s" "$gitDirName"
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
    else
        echo "Could not clone dir %s as directory not empty!" "$dirName"
    fi
}
#endregion


#region user interaction; runtime environment / permissions


#ensure the os is the right version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$NAME" != "Ubuntu" ] || [ "$VERSION_ID" != "18.04" ]; then
        echo "The installer requires os version: *** Ubuntu 18.04 *** "
        echo "Detected version: {$NAME}_{$VERSION_ID}"
        echo "EPICS will install properly, but the GUI may not work. Continue? [Y/n]" 

        read ans
        ans=${ans,,}
        if [ "$ans" == "n" || "$ans" == "no" ]; then 
            echo "Quitting"
            exit 1
        else
            :
        fi

    fi
fi




#Ensure the script is run with sudo:
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires sudo privileges to work properly. Rerunning as sudo:"
    sudo bash "$0" "$@" --source-path "$SCRIPT_DIR" 

    exit 0 #exit original script after rerunning with sudo
fi
ORIGINAL_USER="${SUDO_USER:-${USER:-root}}"
ORIGINAL_USER_HOME=$(eval echo "~$ORIGINAL_USER")


#-------------------------Better to run all prompts first, _then_ proceed with deletions

#Detect/remove previous installations in $EPICS_ROOT
if [ -d $EPICS_ROOT ] && [ -n "$EPICS_ROOT" ]; then
    printf "Existing EPICS installation detected at %s. Installation cannot proceed with existing files.\nRemove previous EPICS installation and reinstall? [y/N]:" "$EPICS_ROOT"
    read response

    response=${response,,}
    if [[ "$response" == "y" || "$response" == "yes" ]]; then #default yes unless explicit No
        echo "Removing previous installation." 
        rm -rf "$EPICS_ROOT"
    else 
        echo "Installation aborted"
        exit 1
    fi
fi

mkdir -p "$EPICS_ROOT"


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
    if [ "$sysEnv" == "WSL" ]; then
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


#if packages dir does not exist or is empty, create it & populate with .deb files
if [ ! -f "$DEPENDENCIES_DIR/$PACKAGES_ZIP" ]; then 
    echo "Local dependency file collection not found. Creating..."

    if check_internet; then
        echo "Downloading relevant dependency files"
        mkdir "$DEPENDENCIES_DIR/packageRepo"

        sudo apt-get update
        sudo apt-get install --download-only -y "${dependenciesList[@]}"
        
        mv /var/cache/apt/archives/*.deb "$DEPENDENCIES_DIR/packageRepo"
        
        # Create the zip
        zip -r "$DEPENDENCIES_DIR/$ACKAGES_ZIP" "$DEPENDENCIES_DIR/packageRepo"
        rm -r "$DEPENDENCIES_DIR/packageRepo"
    
        echo "Dependency files downloaded!"
    else
        printf "Dependency files for Ubuntu $VERSION_ID missing!\nNo internet connection found!\n\nThe installation cannot continue. Please connect to the internet and run the script again."
    fi

fi


#unzip "$FILES_DIR/packages.zip" -d "$FILES_DIR/offline-packages"
unzip "$DEPENDENCIES_DIR/$PACKAGES_ZIP" -d /var/cache/apt/archives/
apt install /var/cache/apt/archives/*.deb 
#dpkg -i "$FILES_DIR/offline-packages/*.deb"


command -v git >/dev/null 2>&1 || { echo "git not found"; exit 1; } #validate git, make
command -v make >/dev/null 2>&1 || { echo "make not found"; exit 1; }

#surplus libxp files called for by epics-base
dpkg -i "$DEPENDENCIES_DIR/libxp6_1.0.2-1ubuntu1_amd64.deb"
dpkg -i "$DEPENDENCIES_DIR/libxp-dev_1.0.2-1ubuntu1_amd64.deb"

echo "Successfully installed dependencies"


#endregion

# ---------------------------------------------------
# Validate, copy .git repositories 
# ---------------------------------------------------

#region git

#github links; backups. Repository clones should be included in localFiles
baseLink='https://github.com/epics-base/epics-base'
extensionsLink='https://github.com/epics-extensions/extensions'
edmLink='https://github.com/epicsdeb/edm.git'
guiLink='https://github.com/MattiasHenders/epics-gui-triumf.git'
fontsLink='https://github.com/silnrsi/font-ttf'

cloneGitRepo $baseLink $EPICS_BASE "EPICS Base" "base"
cloneGitRepo $extensionsLink $EPICS_EXTENSIONS "EPICS Extensions" "extensions"
cloneGitRepo $edmLink $EDM_DIR "EDM" "edm"
cloneGitRepo $guiLink $EPICS_GUI "EPICS GUI" "epics-gui-triumf"
cloneGitRepo $fontsLink $FONTS_DIR "FONTS" "font-ttf"


#endregion


# ---------------------------------------------------
# Prepare ExtensionsTop
# ---------------------------------------------------

tar xvzf $FILES_DIR/extensionsTop_20120904.tar.gz -C $EPICS_ROOT #creates extensions dir

# ---------------------------------------------------
# Build EPICS Base
# ---------------------------------------------------

#region epicsBase

#adds paths to current shell (root: epics_installer.sh)
export EPICS_BASE="$EPICS_BASE" 
export EPICS_EXTENSIONS="$EPICS_EXTENSIONS"
export EPICS_HOST_ARCH="$EPICS_HOST_ARCH"
export HOST_ARCH="$EPICS_HOST_ARCH"

export PATH="$EPICS_BASE/bin/$EPICS_HOST_ARCH:$PATH"
export PATH="$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH:$PATH"

export EPICS_CA_AUTO_ADDR_LIST=YES

export EDMBASE="$EDMBASE"
export EDM_DIR="$EDM_DIR"
export EDM="$EDM_DIR/edmMain/O.$EPICS_HOST_ARCH/edm"
export EDMPVOBJECTS="$EDM_DIR/setup"
export EDMOBJECTS="$EDM_DIR/setup"
export EDMHELPFILES="$EDM_DIR/helpFiles"
export EDMFILES="$EDM_DIR/edmMain"
export EDMLIBS="$EPICS_EXTENSIONS/lib/$EPICS_HOST_ARCH"
export EDMFONTFILE="$EDM_DIR/edmMain/fonts.list"

export LD_LIBRARY_PATH="$EDMLIBS:$EPICS_BASE/lib/$EPICS_HOST_ARCH"


echo "Starting EPICS Base make"
make -j"$(nproc)" -C "$EPICS_BASE"

echo "Successfully installed EPICS base"


#add paths to calling user's shell (user invoking sudo)

#check for presence of $EPICS_MARKER in bashrc before appending
#if marker is present, then skip. This avoids duplicates in the event of repeated installer use

EPICS_MARKER="#=======  EPICS ENVIRONMENT VARIABLES ======="
if ! grep -qF "$EPICS_MARKER" "$ORIGINAL_USER_HOME/.bashrc"; then 
    sudo -u "$ORIGINAL_USER" tee -a "$ORIGINAL_USER_HOME/.bashrc" > /dev/null <<EOF

#=======  EPICS ENVIRONMENT VARIABLES =======
export EPICS_BASE="$EPICS_BASE"
export EPICS_EXTENSIONS="$EPICS_EXTENSIONS"
export EPICS_GUI="$EPICS_GUI"
export EPICS_HOST_ARCH="$EPICS_HOST_ARCH"
export HOST_ARCH="$EPICS_HOST_ARCH"

export PATH="$EPICS_BASE/bin/$EPICS_HOST_ARCH:$PATH"
export PATH="$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH:$PATH"

export EPICS_CA_AUTO_ADDR_LIST=YES

export EDM_DIR="$EPICS_EXTENSIONS/src/edm"
export EDMBASE="$EDM_DIR"
export EDM="$EDM_DIR/edmMain/O.$EPICS_HOST_ARCH/edm"

export EDMOBJECTS="$EDM_DIR/setup"
export EDMPVOBJECTS="$EDM_DIR/setup"
export EDMFILES="$EDM_DIR/setup"
export EDMHELPFILES="$EPICS_EXTENSIONS/src/edm/helpFiles"
export EDMLIBS="$EPICS_EXTENSIONS/lib/$EPICS_HOST_ARCH"
export EDMFONTFILE="$EDM_DIR/edmMain/fonts.list"

export EDM_USE_SHARED_LIBS=YES

export LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
source "$EDM_DIR/setup/setup.sh"

#--------------------------------------------

EOF

fi

echo "Succesfully configured EPICS Base"

#endregion

# ---------------------------------------------------
# Clone EDM into Extensions
# ---------------------------------------------------

#region EDM 

#these few lines sketch me out. Too much relative pathing invites errors if anything is updated

cd $EPICS_ROOT 
sed -i -e "21cEPICS_BASE=$EPICS_BASE" -e '25s/^/#/' extensions/configure/RELEASE
sed -i -e '14cX11_LIB=/usr/lib/x86_64-linux-gnu' -e '18cMOTIF_LIB=/usr/lib/x86_64-linux-gnu' extensions/configure/os/CONFIG_SITE.linux-x86_64.linux-x86_64

cd $EDM_DIR
sed -i -e '15s/$/ -DGIFLIB_MAJOR=5 -DGIFLIB_MINOR=1/' giflib/Makefile
sed -i -e 's| ungif||g' giflib/Makefile*

echo "Making edm"
make clean
make
echo "Successfully made edm"

cd setup
sed -i -e '53cfor libdir in baselib lib epicsPv locPv calcPv util choiceButton pnglib diamondlib giflib videowidget' setup.sh
sed -i -e '79d' setup.sh
sed -i -e '81i\ \ \ \ $EDM -add $EDM_DIR/pnglib/O.$ODIR/lib57d79238-2924-420b-ba67-dfbecdf03fcd.so' setup.sh
sed -i -e '82i\ \ \ \ $EDM -add $EDM_DIR/diamondlib/O.$ODIR/libEdmDiamond.so' setup.sh
sed -i -e '83i\ \ \ \ $EDM -add $EDM_DIR/giflib/O.$ODIR/libcf322683-513e-4570-a44b-7cdd7cae0de5.so' setup.sh
sed -i -e '84i\ \ \ \ $EDM -add $EDM_DIR/videowidget/O.$ODIR/libTwoDProfileMonitor.so' setup.sh

HOST_ARCH=$EPICS_HOST_ARCH sh setup.sh

echo "Successfully installed & configured EDM"


#endregion


# ---------------------------------------------------
# Install Fonts 
# ---------------------------------------------------

#region fonts
sed -i 's/\texact$//' $EDM_DIR/edmMain/fonts.list #allow some flexibility with fonts (necessary for compatibility with newer machines)

echo "Prepared fonts"


#endregion

# ---------------------------------------------------
# GUI -- Xming, for WSL instances 
# ---------------------------------------------------

if [ "$sysEnv" == "WSL" ]; then #WSL -- unverified
    xming_fonts_fileName="Xming-fonts-7-7-0-10-setup.exe"

    cp "{$FILES_DIR}/${xming_fonts_fileName}" "$EPICS_GUI/"

    WIN_PATH=$(wslpath -w "$EPICS_GUI/$xming_fonts_fileName")
    #powershell.exe -NoProfile -NonInteractive -Command \
    #"Start-Process -FilePath '$WIN_PATH' -ArgumentList '/VERYSILENT','/NORESTART' -Wait -PassThru | ForEach-Object { exit \$_.ExitCode }"

    echo "$breakerStr" 
    echo "$breakerStr" 
    printf "\n\nManual interaction needed for Xming installation. \n\nSELECT ALL FONTS IN CHECKBOX LIST.\nEnter any value to continue.\n"
    read dummyVar

    powershell.exe -NoProfile -Command "& '$WIN_PATH'" #runs xming_FileName

    exit $?

else    #Native Ubuntu; not necessary
    echo "Xming not needed for Native Linux systems"
    echo "Skipping Xming install"
fi



ls
# ---------------------------------------------------
# End-script processes 
# ---------------------------------------------------

echo "Done!"

echo "To finish the installation, please restart your terminal session"
