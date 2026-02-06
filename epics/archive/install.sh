#!/usr/bin/env bash

#For:	ubuntu 18.04 Bionic Beaver
#
#Jacob Mattie
#j_mattie@live.ca

#note that there was a manual install of openssh-server and [...?] prior to running the script

while [[ $# -gt 0 ]]; do #reads argument: sourcePath if fed in through the sudo rerun (see first section)
  case "$1" in
    --source-path) sourcePath="$2"; shift 2 ;;
    *) break ;;
  esac
done

set -euo pipefail
IFS=$'\n\t'


sourcePath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # the directory from which the script was run

#optional: clones installer into local directory. Facilitates re-use
pth="/home/epics_installer" 
mkdir -p $pth	
cp -r "$sourcePath/." "$pth/" 

debDir="$sourcePath/packages/debFiles"
gitDir="$sourcePath/packages/gitRepos"
filesDir="$sourcePath/packages/extraFiles"


#---------------------------------------------------------
#
# - Verify sudo access
#
#=--------------------------------------------------------

#ensure root/sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires sudo privileges to work properly. Rerunning as sudo."
    sudo bash "$0" "$@" --source-path "$sourcePath"  #rerun with sudo
    
    exit 0  # Exit the original script after re-running
fi

LOGFILE=$sourcePath/logs.txt
ERRFILE="$sourcePath/errs.txt"
if [ -f "$LOGFILE" ]; then
    rm $LOGFILE
fi
if [ -f "$ERRFILE" ]; then
    rm $ERRFILE
fi
exec > >(tee -a "$LOGFILE") 2> >(tee -a "$ERRFILE" >&2) #Split, save logs & error messages to separate files

echo "Starting install process..."

	
mkdir -p $debDir
mkdir -p $gitDir
mkdir -p $filesDir
mkdir -p "/opt/epics/extensions/src"
mkdir -p "/opt/epics/epics-base"



if [ -d "$gitDir/epics-base" ]; then #copy git epics-base
  echo "Copying git files"
  cp -a "$gitDir/epics-base" /opt/epics/
else
  echo "ERROR: epics-base not found in $gitDir. Aborting." >&2
  exit 1
fi

if [ -d "$gitDir/edm" ]; then #copy git edm
  cp -a "$gitDir/edm" /opt/epics/extensions/src/edm
else
  echo "Warning: edm source not found in $gitDir/edm - continuing but edm build will fail" >&2
fi


#---------------------------------------------------------
#
#		Appends lines to bashrc
#
#---------------------------------------------------------
echo "Appending to bashrc"

linesForBashrc=(
  "export PATH=\"/opt/epics/epics-base/bin/linux-x86_64:\$PATH\""
  "export PATH=\"\$EPICS_BASE/bin/linux-x86_64:\$PATH\""
  "export EPICS_BASE=\"/opt/epics/epics-base\""
  "export EPICS_HOST_ARCH=\"linux-x86_64\""
  "export EPICS_CA_AUTO_ADDR_LIST=\"YES\""
  "export EPICS_EXTENSIONS=\"/opt/epics/extensions\""
  "export PATH=\"\$EPICS_EXTENSIONS/bin/\$EPICS_HOST_ARCH:\$PATH\""
  "export EDMPVOBJECTS=\"\$EPICS_EXTENSIONS/src/edm/setup\""
  "export EDMOBJECTS=\"\$EPICS_EXTENSIONS/src/edm/setup\""
  "export EDMHELPFILES=\"\$EPICS_EXTENSIONS/src/edm/helpFiles\""
  "export EDMFILES=\"\$EPICS_EXTENSIONS/src/edm/edmMain\""
  "export EDMLIBS=\"\$EPICS_EXTENSIONS/lib/\$EPICS_HOST_ARCH\""
)

for line in "${linesForBashrc[@]}"; do
  # Check if the line already exists in ~/.bashrc
  if ! grep -Fxq "$line" ~/.bashrc 2>/dev/null; then
    echo "$line" >> ~/.bashrc
  fi
done

source ~/.bashrc #applies bashrc changes

#---------------------------------------------------------
#		Installs software
#
#	branch 3.15 https://github.com/epics-base/epics-base.git
#	https://github.com/epicsdeb/edm.git
#
#---------------------------------------------------------

echo "Installing local .deb files from $debDir"

cd "$debDir"
shopt -s nullglob


debfiles=(*.deb)
if [ "${#debfiles[@]}" -eq 0 ]; then #installs necessary software
  echo "No .deb files found in $debDir; continuing."
else
  # Use dpkg to install all .deb — order doesn't strictly matter if we run fix afterwards
  # But we'll first attempt to install critical ones first (libc/libc-dev) if present
  priority=(libc6*.deb libc6-dev*.deb libc-bin*.deb)
  for p in "${priority[@]}"; do
    for f in $p; do
      [ -f "$f" ] || continue #skip if no matching file
      echo "Installing priority .deb: $f"
      dpkg -i "$f" || true #ignore warnings/errors; dependency issues are expected here
    done
  done

  echo "Installing remaining .deb files"
  dpkg -i ./*.deb || true

  # Attempt to fix broken installs using only local cache / local debs (no network)
  # --no-download ensures apt won't attempt network fetches
  apt-get install -f -y --no-download || {
    echo "apt-get could not fix dependencies with local files alone."
    echo "Try running apt-get update & apt-get install -f on a system with network access"
    # continue anyway - build will probably fail if dependencies missing
  }
fi


EPICS_BASE="/opt/epics/epics-base"
export EPICS_BASE
HOST_ARCH="linux-x86_64"
export HOST_ARCH



#---------------------------------------------------------
#
#		Build epics-base
#
#---------------------------------------------------------
echo "Building EPICS base in $EPICS_BASE"
cd "$EPICS_BASE"

if [ -f "configure/RELEASE" ] || [ -f "configure/CONFIG_SITE" ]; then
  echo "EPICS base has configure files present"
else
  echo "EPICS base missing configure files; aborting"
  exit 1
fi

make clean || true
make

if [ ! -d "$EPICS_BASE/configure" ]; then #verify successful build
  echo "ERROR: $EPICS_BASE/configure missing after build; base build failed"
  exit 1
fi

# Extract or copy the extensionsTop package (contains configure/)
if [ -d "$filesDir/extensions/configure" ]; then
  echo "Copying EPICS extensions configure directory..."
  cp -r "$filesDir/extensions" /opt/epics/
else
  echo "ERROR: extensions configure directory not found — EDM build will fail."
fi

# Create the compatibility symlink expected by older EDM makefiles
ln -sf /opt/epics/extensions/configure /opt/epics/extensions/config


#---------------------------------------------------------
#
#		Edits config files
#
#---------------------------------------------------------
EXT_CONFIG="/opt/epics/extensions/configure/RELEASE"
if [ -f "$EXT_CONFIG" ]; then
  sed -i -e "21cEPICS_BASE=$EPICS_BASE" -e '25s/^/#/' "$EXT_CONFIG"
else
  echo "Warning: $EXT_CONFIG not found; skipping edits"
fi

EXT_CONFIG_SITE="/opt/epics/extensions/configure/os/CONFIG_SITE.linux-x86_64.linux-x86_64"
if [ -f "$EXT_CONFIG_SITE" ]; then
  sed -i -e "14cX11_LIB=/usr/lib/x86_64-linux-gnu" \
         -e "18cMOTIF_LIB=/usr/lib/x86_64-linux-gnu" \
         "$EXT_CONFIG_SITE"
else
  echo "Warning: $EXT_CONFIG_SITE not found; skipping X11/Motif edits"
fi

GIFMF="$EPICS_BASE/../extensions/src/edm/giflib/Makefile"
if [ -f "$GIFMF" ]; then
  sed -i -e '15s/$/ -DGIFLIB_MAJOR=5 -DGIFLIB_MINOR=1/' "$GIFMF"
  sed -i -e 's| ungif||g' "$(dirname "$GIFMF")"/Makefile* || true
else
  echo "Warning: giflib Makefile not found at $GIFMF; skipping gif tweaks"
fi


#---------------------------------------------------------
#
#		Build edm
#
#---------------------------------------------------------
EDM_DIR="/opt/epics/extensions/src/edm"
if [ -d "$EDM_DIR" ]; then
  cd "$EDM_DIR"
  export EPICS_HOST_ARCH=linux-x86_64
  
  make clean || true
  make || {
    echo "EDM build failed. Check above logs for missing dependencies or build errors."
    exit 1
  }
else
  echo "EDM source missing at $EDM_DIR; cannot build." 
fi



SETUP_SH="$EDM_DIR/setup/setup.sh"
success=false

if [ -f "$SETUP_SH" ]; then

  sed -i '/for libdir in/s|=.*|="baselib lib epicsPv locPv calcPv util choiceButton pnglib diamondlib giflib videowidget"|' "$SETUP_SH"

  sed -i '/^fi/i \$EDM -add \$EDMBASE/pnglib/O.\$ODIR/lib57d79238-2924-420b-ba67-dfbecdf03fcd.so' "$SETUP_SH"
  sed -i '/^fi/i \$EDM -add \$EDMBASE/diamondlib/O.\$ODIR/libEdmDiamond.so' "$SETUP_SH"
  sed -i '/^fi/i \$EDM -add \$EDMBASE/giflib/O.\$ODIR/libcf322683-513e-4570-a44b-7cdd7cae0de5.so' "$SETUP_SH"
  sed -i '/^fi/i \$EDM -add \$EDMBASE/videowidget/O.\$ODIR/libTwoDProfileMonitor.so' "$SETUP_SH"

  success=true
else
  echo "setup.sh not found; skipping setup edits"
fi


if [ "$success" = true ]; then
    HOST_ARCH=$HOST_ARCH sh "$SETUP_SH"
fi