#!/bin/bash


#About this script:

#Paths have been changed to absolute paths for clarity & reproducibility
#"cd", "sudo -i" commands have been removed where possible, since the installer should be run at sudo level anyways

#apt installs have been relegated to a dedicated folder of .deb files.
#This is a response to many of the installs being deprecated (e.g. x11proto-print-dev)

#Moving forwards, the contents of git repositories (e.g. https://github.com/epicsdeb/edm.git) should also be frozen for isolated reproducibility



#---------------------------------------------------------
#
#		Program variables
#
#
# - Only core installation directories lol
# - Program paths build off of here
#
#---------------------------------------------------------

echo "enter core directory, or leave blank for default </home/EPICS>"
read coreDir

if [ -z "$coreDir" ]; then
    mainDirPath="/home/EPICS"
else
    mainDirPath="$coreDir"
fi



mainDirPath='main/directory/path'
debFolderPath='path/to/folder/withDebFiles'
githubFilesPath='path/to/github/installation/dir'


mkdir -p /opt/epics/extensions/src

apt-get update
apt --fix-broken install

#---------------------------------------------------------
#
#		Appends lines to bashrc
#
#---------------------------------------------------------

#single quotes are better for outer wrappings

linesForBashrc=(
  'export PATH="$PATH:$coreDir"'
  'export PATH="$PATH:$debFolderPath"'
  'export PATH="$PATH:$githubFilesPath"'
  "export PATH='/opt/epics/epics-base/bin/linux-x86_64:$PATH'"
  
  "export EPICS_BASE='/opt/epics/epics-base'"
  "export EPICS_HOST_ARCH='linux-x86_64'"
  "export EPICS_CA_AUTO_ADDR_LIST='YES'"
  "export EPICS_EXTENSIONS='/opt/epics/extensions'"
  "export PATH='$EPICS_EXTENSIONS/bin/$EPICS_HOST_ARCH:$PATH'"
  "export EDMPVOBJECTS='$EPICS_EXTENSIONS/src/edm/setup'"
  "export EDMOBJECTS='$EPICS_EXTENSIONS/src/edm/setup'"
  "export EDMHELPFILES='$EPICS_EXTENSIONS/src/edm/helpFiles'"
  "export EDMFILES='$EPICS_EXTENSIONS/src/edm/edmMain'"
  "export EDMLIBS='$EPICS_EXTENSIONS/lib/$EPICS_HOST_ARCH'"
)


for line in "${linesForBashrc[@]}"; do
	echo "$line" >> ~/.bashrc
done
	
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
#---------------------------------------------------------

dpkg -i "$debFolderPath"/*.deb
##git repositories are saved in the gitRepos folder -- these don't need to be installed, just copied into their intended directories


#extensionsTop_[] is included in debFolderPath
#it needs to be unpacked; this occurs here
tar xzvf extensionsTop_20120904.tar.gz -C /opt/epics

sudo apt --fix-broken install -y

#---------------------------------------------------------
#
#		Edits config files
#
#---------------------------------------------------------
#
#
#Be careful with the sed operations -- these edit the files indicated. Validate!
#typical format is: sed 's/oldWord/newWord/' fileName
#appending arguments: how many elements to replace within a line? Default: First only


#-i <-- edit in place
#-e <-- Allow multiple commands
#The script is formatted with -e because there are several edits necessary for each file
#General sed format:
#        - sed -i -e '<lineNumber><operator><argument> <targetFile>
#                OPERATORS:
#                c change
#                d delete
#                i insert BEFORE selected line
#                a append AFTER selected line
#                s substitute part of the line (regex) -- 10s/foo/bar -- replaces first instance (on line 10) of foo with bar
#                        Can append the argument /g to substitute ALL occurrences
#

sudo sed -i -e '21cEPICS_BASE=/opt/epics/epics-base' -e '25s/^/#/' /opt/epics/epics-base/configure/RELEASE
sudo sed -i -e '14cX11_LIB=/usr/lib/x86_64-linux-gnu' -e '18cMOTIF_LIB=/usr/lib/x86_64-linux-gnu' /opt/epics/extensions/configure/os/CONFIG_SITE.linux-x86_64.linux-x86_64

sudo sed -i -e '15s/$/ -DGIFLIB_MAJOR=5 -DGIFLIB_MINOR=1/' /opt/epics/extensions/src/edm/giflib/Makefile
sudo sed -i -e 's| ungif||g' /opt/epics/extensions/src/edm/giflib/Makefile*

#for 
sudo sed -i -e '53cfor libdir in baselib lib epicsPv locPv calcPv util choiceButton pnglib diamondlib giflibvideowidget' /opt/epics/extensions/src/setup/edm/setup.sh
sudo sed -i -e '79d' /opt/epics/extensions/src/setup/edm/setup.sh
sudo sed -i -e '81i\ \ \ \ $EDM -add $EDMBASE/pnglib/O.$ODIR/lib57d79238-2924-420b-ba67-dfbecdf03fcd.so' /opt/epics/extensions/src/setup/edm/setup.sh
sudo sed -i -e '82i\ \ \ \ $EDM -add $EDMBASE/diamondlib/O.$ODIR/libEdmDiamond.so' /opt/epics/extensions/src/setup/edm/setup.sh
sudo sed -i -e '83i\ \ \ \ $EDM -add $EDMBASE/giflib/O.$ODIR/libcf322683-513e-4570-a44b-7cdd7cae0de5.so' /opt/epics/extensions/src/setup/edm/setup.sh
sudo sed -i -e '84i\ \ \ \ $EDM -add $EDMBASE/videowidget/O.$ODIR/libTwoDProfileMonitor.so' /opt/epics/extensions/src/setup/edm/setup.sh


#---------------------------------------------------------
#
#		Appends lines to bashrc
#
#---------------------------------------------------------
cd /opt/epics/epics-base
sudo make

cd /opt/epics/extensions/src/edm
sudo make clean
sudo make

