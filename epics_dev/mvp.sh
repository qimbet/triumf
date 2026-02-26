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
EPICS_HOST_ARCH="linux-x86_64"

# Root directory for EPICS installation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$SCRIPT_DIR/installerFiles"

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

# Ensure required directories exist
mkdir -p "$EPICS_ROOT"

dependenciesList=( #used by apt install
    dpkg-dev make wine-stable 
    build-essential git iperf3 nmap openssh-server vim libreadline-gplv2-dev libgif-dev libmotif-dev libxmu-dev
    libxmu-headers libxt-dev libxtst-dev xfonts-100dpi xfonts-75dpi x11proto-print-dev autoconf libtool sshpass
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
        echo "EPICS will install properly, but the GUI will not work. Continue? [Y/n]" #edit for accuracy after release!!

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


#Detect/remove previous installations in $EPICS_ROOT
if [ -d $EPICS_ROOT ] && [ -n "$EPICS_ROOT" ]; then
    printf "Existing EPICS installation detected at %s. Installation cannot proceed with existing files.\nRemove previous EPICS installation and reinstall? [Y/n]:" "$EPICS_ROOT"
    read response

    response=${response,,}
    if [[ "$response" == "n" || "$response" == "no" ]]; then #default yes unless explicit No
        echo "Installation aborted"
        exit 1
    else 
        echo "Removing previous installation." 
        rm -rf "$EPICS_ROOT"
    fi
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
if [ "$response" == "n" || "$response" == "no" ]; then
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
        echo ""
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

#else #disable online apt repo --- WARNING: ensure they are re-enabled afterwards with: mv /etc/apt/sources.list.d/disabled/*.list /etc/apt/sources.list.d/
    #echo "Disabling online repo"
    #mkdir -p /etc/apt/sources.list.d/disabled
    #mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/disabled/
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


    if [ "$sysEnv" == "WSL" ]; then #resync clock; else apt update/install break
        echo "Resyncing time"
        WIN_TIME=$(cmd.exe /c "powershell -Command Get-Date -Format 'yyyy-MM-dd HH:mm:ss'" | sed 's/\r//')
        date -s "$WIN_TIME"
    fi

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

#adds paths to current shell (root: installer.sh)
export EPICS_BASE="$EPICS_BASE" 
export EPICS_EXTENSIONS="$EPICS_EXTENSIONS"
export EPICS_HOST_ARCH="$EPICS_HOST_ARCH"
export HOST_ARCH="$EPICS_HOST_ARCH"

export PATH="$EPICS_BASE/bin/$EPICS_HOST_ARCH:$PATH"
export PATH="$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH:$PATH"

export EPICS_CA_AUTO_ADDR_LIST=YES

export EDMBASE="$EDMBASE"
export EDM="$EDM_DIR/edmMain/O.$EPICS_HOST_ARCH/edm"
export EDMPVOBJECTS="$EDM_DIR/setup"
export EDMOBJECTS="$EDM_DIR/setup"
export EDMHELPFILES="$EDM_DIR/helpFiles"
export EDMFILES="$EDM_DIR/edmMain"
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
export EPICS_HOST_ARCH="$EPICS_HOST_ARCH"
export HOST_ARCH="$EPICS_HOST_ARCH"

export PATH="$EPICS_BASE/bin/$EPICS_HOST_ARCH:\$PATH"
export PATH="$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH:\$PATH"

export EPICS_CA_AUTO_ADDR_LIST=YES

export EDMBASE="$EDM_DIR"
export EDM="$EDM_DIR/edmMain/O.$EPICS_HOST_ARCH/edm"
export EDMOBJECTS="$EDM_DIR/setup"
export EDMPVOBJECTS="$EDM_DIR/setup"
export EDMFILES="$EDM_DIR/setup"
export EDMHELPFILES="$EPICS_EXTENSIONSsrc/edm/helpFiles"
export EDMLIBS="$EPICS_EXTENSIONS/lib/$EPICS_HOST_ARCH"
export EDM_USE_SHARED_LIBS=YES

export LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
source $EDM_DIR/setup/setup.sh 

EOF

fi

echo "Succesfully configured EPICS Base"

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
#make -j"$(nproc)" -C "$EDM_DIR"
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

if [ "$sysEnv" == "WSL" ]; then #WSL
    xming_fileName="Xming-6-9-0-31-setup.exe"   
    cp "{$FILES_DIR}/{$xming_fileName}" "$EPICS_GUI/"

    WIN_PATH=$(wslpath -w "$EPICS_GUI/$xming_fileName") #convert to windows-appropriate path

    #powershell.exe -NoProfile -NonInteractive -Command \
    #"Start-Process -FilePath '$WIN_PATH' -ArgumentList '/VERYSILENT','/NORESTART' -Wait -PassThru | ForEach-Object { exit \$_.ExitCode }"

    echo "$breakerStr" 
    echo "$breakerStr" 
    printf "\n\nManual interaction needed for Xming installation. \nProceed with all defaults suggested by Xming GUI.\nEnter any value to continue.\n"
    read dummyVar

    powershell.exe -NoProfile -Command "& '$WIN_PATH'" #runs xming_FileName

    exit $?


else #Ubuntu installation process
    ffName="FontForge-2025-10-09-Linux-x86_64.AppImage"

    cp "$FILES_DIR/$ffName" $FONTS_DIR/
    chmod +x "$FONTS_DIR/$ffName"

    if [ ! -e /usr/local/bin/fontforge ]; then
        ln -s "$FONTS_DIR/$ffName" /usr/local/bin/fontforge #only create link if not exists
    fi

    perl Makefile.pl #this may be equivalent to libfont-ttf-perl.deb?
    make -j"$(nproc)" -C "$FONTS_DIR" full-ttf #builds all fonts with all glyphs
    make install -C "$FONTS_DIR"

    echo "Prepared fonts"
fi


#endregion

# ---------------------------------------------------
# GUI -- Xming, for WSL instances 
# ---------------------------------------------------


if [ "$sysEnv" == "WSL" ]; then #WSL
    xming_fonts_fileName="Xming-fonts-7-7-0-10-setup.exe"

    cp "{$FILES_DIR}/{$xming_fonts_fileName}" "$EPICS_GUI/"

    WIN_PATH=$(wslpath -w "$EPICS_GUI/$xming_fileName")
    #powershell.exe -NoProfile -NonInteractive -Command \
    #"Start-Process -FilePath '$WIN_PATH' -ArgumentList '/VERYSILENT','/NORESTART' -Wait -PassThru | ForEach-Object { exit \$_.ExitCode }"

    echo "$breakerStr" 
    echo "$breakerStr" 
    printf "\n\nManual interaction needed for Xming installation. \n\nSELECT ALL FONTS IN CHECKBOX LIST.\nEnter any value to continue.\n"
    read dummyVar

    powershell.exe -NoProfile -Command "& '$WIN_PATH'" #runs xming_FileName

    exit $?

else    #Native Ubuntu; not necessary
    echo "Xming not needed for Native Linux"
    echo "Skipping Xming install"
fi



# ---------------------------------------------------
# Matthias Henders GUI install // epics-gui-triumf.git
# ---------------------------------------------------

#region Matthias Henders GUI install

#endregion


# ---------------------------------------------------
# End-script processes 
# ---------------------------------------------------

echo "Done!"
