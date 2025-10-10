#!/bin/bash


#For:	ubuntu 18.04 Bionic Beaver
#
#Jacob Mattie
#j_mattie@live.ca


#---------------------------------------------------------
#
# - Verify sudo access
# - Prompt for directories
#
#=--------------------------------------------------------
echo "Enter an installation directory, or leave blank for default </home/epics>"
read epicsInstallDir 

if [ -z "$coreDir" ]; then
	pth="/home/epics"
else
    pth="$epicsInstallDir"
fi


if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires sudo privileges to work properly. Please run as sudo."
    #sudo "$0" "$@"  # Re-run the script with sudo
    exit 0  # Exit the original script after re-running with sudo
fi


#---------------------------------------------------------
#
#		apt-get update --- IF internet connection
#
#=--------------------------------------------------------
checkInternet(){
	ping -q -c 1 -W 2 8.8.8.8 < /dev/null
	return $?
}

if checkInternet; then
	apt-get update 
	apt --fix-broken install
else
	echo "No internet connectivity detected. Skipping system updates"
fi

#---------------------------------------------------------
#
#		Appends lines to bashrc
#
#---------------------------------------------------------
#single quotes are better for outer wrappings

linesForBashrc=(
  'export PATH="$PATH:$pth"'
  'export PATH="$PATH:$githubFilesPath"'

  'export PATH="/opt/epics/epics-base/bin/linux-x86_64:$PATH"'
  'export PATH="$EPICS_BASE/bin/linux-x86_64:$PATH"'
  'export EPICS_BASE="/opt/epics/epics-base"'
  'export EPICS_HOST_ARCH="linux-x86_64"'
  'export EPICS_CA_AUTO_ADDR_LIST="YES"'
  'export EPICS_EXTENSIONS="/opt/epics/extensions"'
  'export PATH="$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH:$PATH"'
  'export EDMPVOBJECTS="$EPICS_EXTENSIONS/src/edm/setup"'
  'export EDMOBJECTS="$EPICS_EXTENSIONS/src/edm/setup"'
  'export EDMHELPFILES="$EPICS_EXTENSIONS/src/edm/helpFiles"'
  'export EDMFILES="$EPICS_EXTENSIONS/src/edm/edmMain"'
  'export EDMLIBS="$EPICS_EXTENSIONS/lib/$EPICS_HOST_ARCH"'

  'alias bashrc="vim ~/.bashrc"'
  'alias src="source ~/.bashrc"'
)

for line in "${linesForBashrc[@]}"; do
  # Check if the line already exists in ~/.bashrc
  if ! grep -Fxq "$line" ~/.bashrc; then
    # If the line doesn't exist, append it to ~/.bashrc
    echo "$line" >> ~/.bashrc
  fi
done


source ~/.bashrc

#---------------------------------------------------------
#
#		Program Paths 
#		  ' is a literal
#		  " expands variables
#----------------------------------------------------------
epicsBase=$"/opt/epics"
mkdir -p $pth	#default: /home/epics 
mkdir -p "$epicsBase/extensions/src"

sourcePath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
	#^ the directory from which the script was run

cp -r $sourcePath $pth #clones; creates local copy

packageExt='packages'
debExt='debFiles'
githubExt='gitRepos'
filesExt='extraFiles'

packageOrigin="$pth/$packageExt"

debDir="$packageOrigin/$debExt"
gitDir="$packageOrigin/$githubExt"
filesDir="$packageOrigin/$filesExt"

cp $gitDir/epics-base $epicsBase
cp $gitDir/edm "$epicsBase/extensions/src/"

echo "alias epicsDir=\"cd $pth\"" >> ~/.bashrc #add alias to bashrc

#---------------------------------------------------------
#		Installs software
#
#  Software files (.deb, github repos) are imported in a bundled .tar file
#
#
#	branch 3.15 https://github.com/epics-base/epics-base.git
#	https://github.com/epicsdeb/edm.git
#
#=--------------------------------------------------------
#sudo apt-get install build-essential git iperf3 nmap openssh-server vim libreadline-gplv2-dev libgif-dev libmotif-dev libxmu-dev libxmu-headers libxt-dev libxtst-dev xfonts-100dpi xfonts-75dpi x11proto-print-dev autoconf libtool sshpass

cp -r "$gitDir/epics-base" $epicsBase
cp -r "$filesDir/extensions" $epicsBase

dpkg -i "$debDirPath"/*.deb

#---------------------------------------------------------
#
#		Edits config files
#
#---------------------------------------------------------

sed -i -e "21cEPICS_BASE=$epicsBase/epics-base" -e '25s/^/#/' 					$epicsBase/epics-base/configure/RELEASE
sed -i -e '14cX11_LIB=/usr/lib/x86_64-linux-gnu' -e '18cMOTIF_LIB=/usr/lib/x86_64-linux-gnu' 	$epicsBase/extensions/configure/os/CONFIG_SITE.linux-x86_64.linux-x86_64
sed -i -e '15s/$/ -DGIFLIB_MAJOR=5 -DGIFLIB_MINOR=1/' 						$epicsBase/epics/extensions/src/edm/giflib/Makefile
sed -i -e 's| ungif||g' 									$epicsBase/extensions/src/edm/giflib/Makefile*
sed -i -e '53cfor libdir in baselib lib epicsPv locPv calcPv util choiceButton pnglib diamondlib giflibvideowidget' $epicsBase/extensions/src/edm/setup/setup.sh
sed -i -e '79d' 											$epicsBase/extensions/src/edm/setup/setup.sh
sed -i -e '81i\ \ \ \ $EDM -add $EDMBASE/pnglib/O.$ODIR/lib57d79238-2924-420b-ba67-dfbecdf03fcd.so' 	$epicsBase/extensions/src/edm/setup/setup.sh
sed -i -e '82i\ \ \ \ $EDM -add $EDMBASE/diamondlib/O.$ODIR/libEdmDiamond.so' 				$epicsBase/extensions/src/edm/setup/setup.sh
sed -i -e '83i\ \ \ \ $EDM -add $EDMBASE/giflib/O.$ODIR/libcf322683-513e-4570-a44b-7cdd7cae0de5.so' 	$epicsBase/extensions/src/edm/setup/setup.sh
sed -i -e '84i\ \ \ \ $EDM -add $EDMBASE/videowidget/O.$ODIR/libTwoDProfileMonitor.so' 			$epicsBase/extensions/src/edm/setup/setup.sh


#---------------------------------------------------------
#
#		Builds EPICS
#
#=--------------------------------------------------------

cd $epicsBase/epics-base 
#make
#
#cd $epicsBase/extensions/src/edm
#make clean
#make


