#!/bin/bash


#About this script:

#Paths have been changed to absolute paths for clarity & reproducibility
#"cd", "sudo -i" commands have been removed where possible, since the installer should be run at sudo level anyways

#apt installs have been relegated to a dedicated folder of .deb files.
#This is a response to many of the installs being deprecated (e.g. x11proto-print-dev)

#Moving forwards, the contents of git repositories (e.g. https://github.com/epicsdeb/edm.git) should also be frozen for isolated reproducibility


#---------------------------------------------------------
#
#		Housekeeping
#
#=--------------------------------------------------------

#apt-get update 
#apt --fix-broken install

#---------------------------------------------------------
#
#		UI
#
# - Verify sudo access
# - Prompt for directories
#
#=--------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires sudo privileges to work properly. Please run as sudo."
    #sudo "$0" "$@"  # Re-run the script with sudo
    exit 0  # Exit the original script after re-running with sudo
fi


echo "Enter an installation directory, or leave blank for default </home/EPICS>"
read coreDir 

if [ -z "$coreDir" ]; then
	installationTargetPath="/home/epics"
else
    installationTargetPath="$coreDir"
fi

#---------------------------------------------------------
#
#		Program variables
#
#
# - Only core installation directories lol
# - Program paths build off of here
#
#=---------------------------------------------------------

coreSourcePath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sourcePath='$coreSourcePath/packages'

debDirName='debFiles'
githubDirName='gitRepos'

debDirPath="$installationTargetPath/$debDirName"
gitDirPath="$installationTargetPath/$githubDirName"

sudo mkdir -p $installationTargetPath
sudo mkdir -p /opt/epics/

sudo cp -r $sourcePath $installationTargetPath 

sudo mv $gitDirPath/epics-base /opt/epics/
sudo mv $gitDirPath/edm /opt/epics/extensions/src/


#---------------------------------------------------------
#
#		Appends lines to bashrc
#
#=--------------------------------------------------------

#single quotes are better for outer wrappings

linesForBashrc=(
  'export PATH="$PATH:$installationTargetPath"'
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
#		Installs software
#
#
#  Software files (.deb, github repos) are imported in a bundled .tar file
#
#
#  If needed, original git links are here:
#	sudo git clone --branch 3.15 https://github.com/epics-base/epics-base.git
#	sudo git clone https://github.com/epicsdeb/edm.git
#
#=--------------------------------------------------------

#unpack .tar file 
dpkg -i "$debDirPath"/*.deb

tar xzvf $installationTargetPath/extensionsTop_20120904.tar.gz -C /opt/epics
#sudo rm $installationTagetPath/extensionsTop_20120904.tar.gz


#---------------------------------------------------------
#
#		Edits config files
#
#=--------------------------------------------------------

#Sed operations edit the files indicated. 

#typical format is: sed 's/oldWord/newWord/' fileName

#-i <-- edit in place
#-e <-- Allow multiple commands on the given file
#General sed format:
#        - sed -i -e '<lineNumber><operator><argument> <targetFile>
#                OPERATORS:
#                c change
#                d delete
#                i insert BEFORE selected line
#                a append AFTER selected line
#                s substitute part of the line (regex) -- 10s/foo/bar -- replaces first instance of foo with bar
#                        Can append the argument /g to substitute ALL occurrences
#

sed -i -e '21cEPICS_BASE=/opt/epics/epics-base' -e '25s/^/#/' 					/opt/epics/epics-base/configure/RELEASE
sed -i -e '14cX11_LIB=/usr/lib/x86_64-linux-gnu' -e '18cMOTIF_LIB=/usr/lib/x86_64-linux-gnu' 	/opt/epics/extensions/configure/os/CONFIG_SITE.linux-x86_64.linux-x86_64

sed -i -e '15s/$/ -DGIFLIB_MAJOR=5 -DGIFLIB_MINOR=1/' 						/opt/epics/extensions/src/edm/giflib/Makefile
sed -i -e 's| ungif||g' 									/opt/epics/extensions/src/edm/giflib/Makefile*

sed -i -e '53cfor libdir in baselib lib epicsPv locPv calcPv util choiceButton pnglib diamondlib giflibvideowidget' /opt/epics/extensions/src/edm/setup/setup.sh
sed -i -e '79d' 											/opt/epics/extensions/src/edm/setup/setup.sh
sed -i -e '81i\ \ \ \ $EDM -add $EDMBASE/pnglib/O.$ODIR/lib57d79238-2924-420b-ba67-dfbecdf03fcd.so' 	/opt/epics/extensions/src/edm/setup/setup.sh
sed -i -e '82i\ \ \ \ $EDM -add $EDMBASE/diamondlib/O.$ODIR/libEdmDiamond.so' 				/opt/epics/extensions/src/edm/setup/setup.sh
sed -i -e '83i\ \ \ \ $EDM -add $EDMBASE/giflib/O.$ODIR/libcf322683-513e-4570-a44b-7cdd7cae0de5.so' 	/opt/epics/extensions/src/edm/setup/setup.sh
sed -i -e '84i\ \ \ \ $EDM -add $EDMBASE/videowidget/O.$ODIR/libTwoDProfileMonitor.so' 			/opt/epics/extensions/src/edm/setup/setup.sh


#---------------------------------------------------------
#
#		Builds EPICS
#
#=--------------------------------------------------------

#cd /opt/epics/epics-base 
#make
#
#cd /opt/epics/extensions/src/edm
#make clean
#make

