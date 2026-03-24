#!/bin/sh

SCRIPT_DIR=$(
    CDPATH='' cd -- "$(dirname -- "$0")" && pwd
)

usage() {
    cat <<'EOF'
Usage:
  ./auto_install.sh <package> <router> [version]

Arguments:
  <package>  Package name:
             antiblock | yubikey-hack | dns-client-test |
             domains-block-test | dns-server-test |
             luci-app-antiblock | QUICTun

  <router>   SSH host, for example:
             router
             root@192.168.1.1

  [version]  Optional OpenWrt version.
             If omitted, version is read from the router.

Mode:
  no version  -> build and install on router
  version     -> build only, save apk locally
EOF
}

is_valid_package() {
    case "$1" in
        antiblock | \
            yubikey-hack | \
            dns-client-test | \
            domains-block-test | \
            dns-server-test | \
            luci-app-antiblock | \
            QUICTun)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

install_host_dependencies() {
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
            wget \
            curl
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
            wget \
            curl
    fi
}

require_ssh() {
    if ! ssh -o StrictHostKeyChecking=no "$ROUTER_NAME" \
        cat /etc/os-release >/dev/null 2>&1; then
        echo "SSH connection or remote command failed: $ROUTER_NAME"
        exit 1
    fi
}

extract_os_release_value() {
    key="$1"
    printf '%s\n' "$ROUTER_OS_RELEASE" \
        | sed -n "s/^${key}=\"\\(.*\\)\"$/\\1/p" \
        | head -n 1
}

fetch_sdk_archive_name() {
    curl -fsSL "$SDK_WEB_FOLDER" 2>/dev/null \
        | awk '
            match($0, /href="([^"]*sdk[^"]*)"/, a) {
                print a[1]
                exit
            }
        '
}

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\/&|]/\\&/g'
}

generate_build_script() {
    template_path="$1"
    output_path="$2"

    if [ ! -f "$template_path" ]; then
        echo "Template file not found: $template_path"
        exit 1
    fi

    package_build_name_esc=$(escape_sed_replacement "$PACKAGE_BUILD_NAME")
    package_name_esc=$(escape_sed_replacement "$PACKAGE_NAME")
    router_name_esc=$(escape_sed_replacement "$ROUTER_NAME")
    board_arch_esc=$(escape_sed_replacement "$BOARD_ARCH")
    copy_only_esc=$(escape_sed_replacement "$COPY_ONLY")

    sed \
        -e "s|@PACKAGE_BUILD_NAME@|$package_build_name_esc|g" \
        -e "s|@PACKAGE_NAME@|$package_name_esc|g" \
        -e "s|@ROUTER_NAME@|$router_name_esc|g" \
        -e "s|@BOARD_ARCH@|$board_arch_esc|g" \
        -e "s|@COPY_ONLY@|$copy_only_esc|g" \
        "$template_path" >"$output_path"

    chmod +x "$output_path"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    usage
    exit 1
fi

PACKAGE_NAME="$1"
ROUTER_NAME="$2"
OPENWRT_VERSION="${3:-}"

if ! is_valid_package "$PACKAGE_NAME"; then
    echo "Argument 1: invalid package name: $PACKAGE_NAME"
    echo
    usage
    exit 1
fi

install_host_dependencies
require_ssh

ROUTER_OS_RELEASE="$(ssh "$ROUTER_NAME" cat /etc/os-release)"

if [ -n "$OPENWRT_VERSION" ]; then
    VERSION="$OPENWRT_VERSION"
else
    VERSION="$(extract_os_release_value VERSION)"
fi

BOARD="$(extract_os_release_value OPENWRT_BOARD)"
BOARD_ARCH="$(extract_os_release_value OPENWRT_ARCH)"

if [ -z "$VERSION" ]; then
    echo "Cannot determine OpenWrt VERSION"
    exit 1
fi

if [ -z "$BOARD" ]; then
    echo "Cannot determine OPENWRT_BOARD"
    exit 1
fi

if [ -z "$BOARD_ARCH" ]; then
    echo "Cannot determine OPENWRT_ARCH"
    exit 1
fi

OPENWRT_DL="https://downloads.openwrt.org/releases"
SDK_WEB_FOLDER="$OPENWRT_DL/$VERSION/targets/$BOARD/"

echo "PACKAGE_NAME: $PACKAGE_NAME"
echo "ROUTER_NAME:  $ROUTER_NAME"
echo "VERSION:      $VERSION"
echo "BOARD:        $BOARD"
echo "BOARD_ARCH:   $BOARD_ARCH"
echo "SDK folder:   $SDK_WEB_FOLDER"
echo

SDK_ARCHIVE="$(fetch_sdk_archive_name)"

if [ -z "$SDK_ARCHIVE" ]; then
    echo "Cannot find SDK archive at: $SDK_WEB_FOLDER"
    exit 1
fi

if [ ! -f "$SDK_ARCHIVE" ]; then
    wget -q "${SDK_WEB_FOLDER}${SDK_ARCHIVE}"
fi

SDK_FOLDER=$(
    printf '%s\n' "$SDK_ARCHIVE" \
        | rev | cut -d'.' -f2- | cut -d'.' -f2- | rev
)

if [ ! -d "$SDK_FOLDER" ]; then
    tar -xf "$SDK_ARCHIVE"
fi

cd "$SDK_FOLDER" || exit 1

sed -i -E \
    's#https://git\.openwrt\.org/[^/]+/#https://github.com/openwrt/#g' \
    feeds.conf.default

./scripts/feeds update -a
./scripts/feeds install -a

ssh -o StrictHostKeyChecking=no git@github.com || true

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

if [ -n "$OPENWRT_VERSION" ]; then
    COPY_ONLY="1"
else
    COPY_ONLY=""
fi

generate_build_script \
    "$SCRIPT_DIR/build_in_sdk.sh.in" \
    "./build_in_sdk.sh"

./build_in_sdk.sh
