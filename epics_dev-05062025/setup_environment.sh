#Validate docker install
#create necessary directories; validate environment space

#create a named volume; -v epics-data:/opt/epics


OS_NAME=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
VERSION_ID=$(lsb_release -rs)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$SCRIPT_DIR/installerFiles"
DEPENDENCIES_DIR="$FILES_DIR/dependencies"
PACKAGES_DIR="${OS_NAME}_${VERSION_ID}"

LOCAL_VERSION_FILES="$DEPENDENCIES_DIR/$PACKAGES_DIR"
DOCKER_ZIP="$LOCAL_VERSION_FILES/Packages.gz"


if [ ! -f "$DOCKER_ZIP" ]; then
    echo "Creating offline cache..."

    apt-get update
    apt-get install -y --download-only --reinstall (docker.io containerd runc)

    cp /var/cache/apt/archives/*.deb "$LOCAL_VERSION_FILES/pool/"

    apt-get install -y dpkg-dev
    cd "$LOCAL_VERSION_FILES"
    dpkg-scanpackages pool /dev/null | gzip -9c > "Packages.gz"
fi


if [ ! -f "${PACKAGES_ZIP%.gz}" ]; then
    gzip -dk "$PACKAGES_ZIP"
fi

echo "deb [trusted=yes] file:$LOCAL_VERSION_FILES/ ./" \
    | tee /etc/apt/sources.list.d/offline.list

apt-get update
apt-get install -y docker.io

#systemctl enable docker
#systemctl start docker
#usermod -aG docker "$ORIGINAL_USER"
#ls -l /var/run/docker.sock









