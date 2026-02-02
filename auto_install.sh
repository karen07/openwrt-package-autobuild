#!/bin/sh

if [ "$1" != "antiblock" ] && [ "$1" != "yubikey-hack" ] \
    && [ "$1" != "dns-client-test" ] && [ "$1" != "domains-block-test" ] \
    && [ "$1" != "dns-server-test" ] && [ "$1" != "luci-app-antiblock" ] \
    && [ "$1" != "QUICTun" ]; then
    echo "Argument 1: Invalid package name"
    echo "Use antiblock or yubikey-hack or dns-client-test or domains-block-test \
or dns-server-test or luci-app-antiblock or QUICTun"
    exit 1
fi

if [ -z "$2" ]; then
    echo "Argument 2: Empty router ssh name"
    exit 1
fi

if [ -f /usr/bin/apt ]; then
    sudo apt update
    sudo apt install -y \
        build-essential \
        libncurses-dev \
        git \
        rsync \
        swig \
        unzip \
        zstd \
        wget
fi

if [ -f /usr/bin/pacman ]; then
    sudo pacman -Sy --noconfirm \
        base-devel \
        python \
        python-setuptools \
        git \
        rsync \
        swig \
        unzip \
        zstd \
        wget
fi

PACKAGE_NAME="$1"
ROUTER_NAME="$2"

if ! ssh -o StrictHostKeyChecking=no "$ROUTER_NAME" cat /etc/os-release; then
    echo "SSH connection or remote command failed"
    exit 1
fi

ROUTER_OS_RELEASE="$(ssh "$ROUTER_NAME" cat /etc/os-release)"

VERSION=$(echo "$ROUTER_OS_RELEASE" \
    | grep VERSION | head -n 1 | cut -d'"' -f2)

BOARD=$(echo "$ROUTER_OS_RELEASE" \
    | grep OPENWRT_BOARD | head -n 1 | cut -d'"' -f2)

OPENWRT_DL="https://downloads.openwrt.org/releases"
SDK_WEB_FOLDER="$OPENWRT_DL/$VERSION/targets/$BOARD/"

SDK_ARCHIVE=$(
    curl -s "$SDK_WEB_FOLDER" \
        | grep -i sdk \
        | awk 'match($0, /href="([^"]+)"/, a) { print a[1] }'
)

if [ ! -f "$SDK_ARCHIVE" ]; then
    wget "${SDK_WEB_FOLDER}${SDK_ARCHIVE}"
fi

SDK_FOLDER=$(
    echo "$SDK_ARCHIVE" \
        | rev | cut -d'.' -f2- | cut -d'.' -f2- | rev
)

if [ ! -d "$SDK_FOLDER" ]; then
    tar -xf "$SDK_ARCHIVE"
fi

cd "$SDK_FOLDER"/ || exit

sed -i -E '
s#https://git\.openwrt\.org/openwrt/openwrt\.git#https://github.com/openwrt/openwrt.git#g;
s#https://git\.openwrt\.org/(feed|project)/#https://github.com/openwrt/#g
' feeds.conf.default

./scripts/feeds update -a
./scripts/feeds install -a

ssh -o StrictHostKeyChecking=no git@github.com

if [ "$PACKAGE_NAME" != "luci-app-antiblock" ]; then
    if [ ! -d "package/$PACKAGE_NAME" ]; then
        if ! git clone --recursive \
            "git@github.com:karen07/$PACKAGE_NAME.git" \
            "package/$PACKAGE_NAME"; then
            git clone --recursive \
                "https://github.com/karen07/$PACKAGE_NAME.git" \
                "package/$PACKAGE_NAME"
        fi
    fi
fi

PACKAGE_BUILD_NAME="${PACKAGE_NAME}-openwrt-package"

if [ ! -d "package/$PACKAGE_BUILD_NAME" ]; then
    if ! git clone --recursive \
        "git@github.com:karen07/$PACKAGE_BUILD_NAME.git" \
        "package/$PACKAGE_BUILD_NAME"; then
        git clone --recursive \
            "https://github.com/karen07/$PACKAGE_BUILD_NAME.git" \
            "package/$PACKAGE_BUILD_NAME"
    fi
fi

cat >auto.sh <<EOF
#!/bin/sh

green=\$(printf '\033[0;32m')
red=\$(printf '\033[0;31m')
reset=\$(printf '\033[0m')

echo "Building $PACKAGE_BUILD_NAME"
echo ""

make defconfig
make package/$PACKAGE_BUILD_NAME/clean

if make -j\$(nproc) package/$PACKAGE_BUILD_NAME/compile; then

    PACKAGE_IPK_PATH=\$(find bin | grep "/${PACKAGE_NAME}_")
    PACKAGE_IPK_NAME=\$(basename "\$PACKAGE_IPK_PATH")

    if [ -f "\$PACKAGE_IPK_PATH" ]; then
        scp -O "\$PACKAGE_IPK_PATH" "$ROUTER_NAME":~/
        ssh "$ROUTER_NAME" opkg remove --force-depends "$PACKAGE_NAME"
        ssh "$ROUTER_NAME" opkg update
        ssh "$ROUTER_NAME" opkg install "\$PACKAGE_IPK_NAME"
        ssh "$ROUTER_NAME" rm "\$PACKAGE_IPK_NAME"
        printf '%sCommand succeeded %s%s\n' "\$green" "$PACKAGE_NAME" "\$reset"
    fi
else
    make -j1 V=s package/$PACKAGE_BUILD_NAME/compile
    printf '%sCommand failed %s%s\n' "\$red" "$PACKAGE_NAME" "\$reset"
fi
EOF

chmod +x auto.sh
./auto.sh
