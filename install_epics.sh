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
        ./methods/epicsInstaller_WSL "$ORIGINAL_USER" "$SCRIPT_DIR"
        ;;
    "Native Ubuntu")
        ./methods/epicsInstaller_Ubuntu "$ORIGINAL_USER" "$SCRIPT_DIR"
        ;;
    "Raspberry Pi")
        ./methods/epicsInstaller_raspberryPi "$ORIGINAL_USER" "$SCRIPT_DIR"
        ;;
    *)
        echo "Unknown environment: $sysEnv" >&2
        exit 1
        ;;
esac