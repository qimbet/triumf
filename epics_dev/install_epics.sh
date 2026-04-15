#!/usr/bin/env bash

#Jacob Mattie
#j_mattie@live.ca

#November, 2025

set -euo pipefail

trap 'echo "ERROR in function ${FUNCNAME[0]:-main}, file ${BASH_SOURCE[1]:${BASH_SOURCE[0]}}, line $LINENO"; exit 1' ERR
caller="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"

#Ensure the script is run with sudo:
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires sudo privileges to work properly. Rerunning as sudo:"
    sudo bash "$0" "$@" --source-path "$SCRIPT_DIR" 

    exit 0 #exit original script after rerunning with sudo
fi

ORIGINAL_USER="${SUDO_USER:-${USER:-root}}"
ORIGINAL_USER_HOME=$(eval echo "~$ORIGINAL_USER")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EPICS_ROOT="/opt/epics" #installation target directory

#prompt to remove preexisting installation
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


#detect system type 
if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version; then
    sysEnv="WSL"
elif [[ -f /proc/device-tree/model ]] && grep -qi "raspberry pi" /proc/device-tree/model; then
    sysEnv="Raspberry Pi"
else
    sysEnv="Native Ubuntu"
fi

printf "Detected environment: %s. Is this correct? [Y/n]: " "$sysEnv"
read -r response
response=${response,,}

# correction menu 
if [[ "$response" == "n" || "$response" == "no" ]]; then
    echo "Select environment:"
    echo "1) WSL"
    echo "2) Raspberry Pi"
    echo "3) Native Ubuntu"
    printf "Choice [1-3]: "
    read -r choice

    case "$choice" in
        1) sysEnv="WSL" ;;
        2) sysEnv="Raspberry Pi" ;;
        3) sysEnv="Native Ubuntu" ;;
        *) echo "Invalid selection, keeping detected value." ;;
    esac
fi

case "$sysEnv" in
    "WSL")
        "$SCRIPT_DIR/methods/epicsInstaller_WSL.sh" "$ORIGINAL_USER" "$SCRIPT_DIR" "$EPICS_ROOT"
        ;;
    "Native Ubuntu")
        "$SCRIPT_DIR/methods/epicsInstaller_Ubuntu.sh" "$ORIGINAL_USER" "$SCRIPT_DIR" "$EPICS_ROOT"
        ;;
    "Raspberry Pi")
        "$SCRIPT_DIR/methods/epicsInstaller_raspberryPi.sh" "$ORIGINAL_USER" "$SCRIPT_DIR" "$EPICS_ROOT"
        ;;
    *)
        echo "Unknown environment: $sysEnv" >&2
        exit 1
        ;;
esac

echo "Done!"


#option to create a local copy of the installer
while true; do
    read -p "Would you like to create a local copy of this epics installer for future use? [Y/n]: " cloneChoice
    cloneChoice=${cloneChoice,,}

    case "$cloneChoice" in 
        ""|y|yes)
            echo "Default directory: $ORIGINAL_USER_HOME"

            read -rp "Press Enter to copy into here, or enter an alternate directory: " target_dir
            target_dir="${target_dir:-$ORIGINAL_USER_HOME}"
    
            mkdir -p "$target_dir"
            cp -r "$SCRIPT_DIR" "$target_dir"

            echo "Installer cloned into: $target_dir"

            break
            ;;
        
        n|no)
            echo "You got it, boss. Nothing done."
            break
            ;;
        
        *)
            echo "Choice not recognized. Try again."
            ;;
    esac
done
    
echo "To use epics, restart your terminal session or run: source ~/.bashrc"
cat <<EOF
Installer completed!
For a quick-start overview about using epics, take a look at the readme.txt

For more in-depth instructions on using epics, read through the pdf files in this installer's Documentation folder.

Epics has been added to your system path. To begin using epics, you can either restart your shell session (open a new terminal/command prompt window) or run:
    source ~/.bashrc

EOF
