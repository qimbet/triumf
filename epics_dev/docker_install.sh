#!/usr/bin/env bash

#Jacob Mattie
#j_mattie@live.ca

#April 2026

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EPICS_ROOT="${EPICS_ROOT:-/opt/epics}"
INSTALL_ENV="${INSTALL_ENV:-Ubuntu}"

mkdir -p "$EPICS_ROOT"

case "$INSTALL_ENV" in
    WSL)
        "$SCRIPT_DIR/methods/epicsInstaller_WSL.sh"
        ;;
    Ubuntu)
        "$SCRIPT_DIR/methods/epicsInstaller_Ubuntu.sh"
        ;;
    RaspberryPi)
        "$SCRIPT_DIR/methods/epicsInstaller_raspberryPi.sh"
        ;;
    *)
        echo "Unknown environment"
        exit 1
        ;;
esac