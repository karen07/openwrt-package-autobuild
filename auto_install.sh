#!/bin/sh

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

GITHUB_OWNER="${GITHUB_OWNER:-karen07}"

PACKAGES="antiblock \
yubikey-hack \
dns-client-test \
domains-block-test \
dns-server-test \
luci-app-antiblock \
QUICTun"

green=$(printf '\033[0;32m')
red=$(printf '\033[0;31m')
reset=$(printf '\033[0m')

usage() {
    cat <<'EOF_USAGE'
Usage:
  ./auto_install.sh install <package> <router>
  ./auto_install.sh build-router <package> <router> <version> [output-dir]
  ./auto_install.sh build-target <package> <version> <target> <subtarget> <pkgarch> [output-dir]

Modes:
  install       Detect version/target/arch from router, build package, install to router.
  build-router  Detect target/arch from router, use explicit version, save package locally.
  build-target  Use explicit version/target/subtarget/pkgarch, save package locally.

Packages:
  antiblock | yubikey-hack | dns-client-test | domains-block-test |
  dns-server-test | luci-app-antiblock | QUICTun | all

Examples:
  ./auto_install.sh install antiblock router
  ./auto_install.sh install all router
  ./auto_install.sh build-router all router 25.12.4
  ./auto_install.sh build-router all router 25.12.4 release
  ./auto_install.sh build-target all 25.12.4 x86 64 x86_64 release
EOF_USAGE
}

die() {
    printf '%s%s%s\n' "$red" "$*" "$reset" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

is_valid_package() {
    case " $PACKAGES " in
        *" $1 "*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

build_package_name() {
    printf '%s-openwrt-package\n' "$1"
}

output_package_name() {
    build_pkg="$1"

    case "$build_pkg" in
        *-openwrt-package)
            printf '%s\n' "${build_pkg%-openwrt-package}"
            ;;
        *)
            printf '%s\n' "$build_pkg"
            ;;
    esac
}

prepare_package_list() {
    printf '%s\n' "$SELECTED_PACKAGES"
}

clone_package() {
    repo="$1"
    dst="package/$repo"

    if [ -d "$dst/.git" ]; then
        echo "Updating $repo -> $dst"

        git -C "$dst" pull --ff-only --recurse-submodules \
            || die "Cannot update $repo"

        git -C "$dst" submodule update --init --recursive \
            || die "Cannot update submodules for $repo"

        return
    fi

    echo "Cloning $repo -> $dst"

    rm -rf "$dst" || die "Cannot remove $dst"

    if GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new' \
        git clone --recursive "git@github.com:$GITHUB_OWNER/$repo.git" "$dst"; then
        return
    fi

    rm -rf "$dst" || die "Cannot remove failed clone: $dst"

    git clone --recursive "https://github.com/$GITHUB_OWNER/$repo.git" "$dst" \
        || die "Cannot clone $repo"
}

prepare_one_package() {
    pkg="$1"

    if [ "$pkg" != "luci-app-antiblock" ]; then
        clone_package "$pkg"
    fi

    clone_package "$(build_package_name "$pkg")"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

MODE="${1:-}"

case "$MODE" in
    install)
        [ "$#" -eq 3 ] || {
            usage
            exit 1
        }

        PACKAGE_NAME="$2"
        ROUTER="$3"
        VERSION=""
        TARGET=""
        SUBTARGET=""
        BOARD=""
        BOARD_ARCH=""
        OUTPUT_DIR=""
        COPY_ONLY=""
        ;;

    build-router)
        [ "$#" -eq 4 ] || [ "$#" -eq 5 ] || {
            usage
            exit 1
        }

        PACKAGE_NAME="$2"
        ROUTER="$3"
        VERSION="$4"
        TARGET=""
        SUBTARGET=""
        BOARD=""
        BOARD_ARCH=""
        OUTPUT_DIR="${5:-}"
        COPY_ONLY=1
        ;;

    build-target)
        [ "$#" -eq 6 ] || [ "$#" -eq 7 ] || {
            usage
            exit 1
        }

        PACKAGE_NAME="$2"
        ROUTER=""
        VERSION="$3"
        TARGET="$4"
        SUBTARGET="$5"
        BOARD="$TARGET/$SUBTARGET"
        BOARD_ARCH="$6"
        OUTPUT_DIR="${7:-}"
        COPY_ONLY=1
        ;;

    *)
        usage
        exit 1
        ;;
esac

if [ "$PACKAGE_NAME" = "all" ]; then
    SELECTED_PACKAGES="$PACKAGES"
elif is_valid_package "$PACKAGE_NAME"; then
    SELECTED_PACKAGES="$PACKAGE_NAME"
else
    die "Invalid package name: $PACKAGE_NAME"
fi

BUILD_PACKAGES=""
for pkg in $SELECTED_PACKAGES; do
    build_pkg="$(build_package_name "$pkg")"
    BUILD_PACKAGES="${BUILD_PACKAGES:+$BUILD_PACKAGES }$build_pkg"
done

for cmd in \
    awk basename cp curl dirname find git \
    head make mkdir nproc pwd readlink rm sed sort \
    tail tar wget; do
    need_cmd "$cmd"
done

if [ -n "$ROUTER" ]; then
    need_cmd ssh

    ssh -o StrictHostKeyChecking=no "$ROUTER" cat /etc/os-release >/dev/null 2>&1 \
        || die "SSH connection failed: $ROUTER"

    OS_RELEASE="$(ssh "$ROUTER" cat /etc/os-release)" \
        || die "Cannot read /etc/os-release from router: $ROUTER"
fi

os_release_value() {
    key="$1"

    printf '%s\n' "$OS_RELEASE" | awk -F= -v key="$key" '
        $1 == key {
            value = $0
            sub(/^[^=]*=/, "", value)
            gsub(/^"|"$/, "", value)
            print value
            exit
        }
    '
}

if [ -n "$ROUTER" ]; then
    [ -n "$VERSION" ] || VERSION="$(os_release_value VERSION)"

    BOARD="$(os_release_value OPENWRT_BOARD)"
    BOARD_ARCH="$(os_release_value OPENWRT_ARCH)"

    TARGET="${BOARD%%/*}"
    SUBTARGET="${BOARD#*/}"
fi

[ -n "$VERSION" ] || die "Cannot determine OpenWrt VERSION"
[ -n "$BOARD" ] || die "Cannot determine OPENWRT_BOARD"
[ -n "$BOARD_ARCH" ] || die "Cannot determine OPENWRT_ARCH"
[ -n "$TARGET" ] || die "Cannot determine OpenWrt target from OPENWRT_BOARD"
[ -n "$SUBTARGET" ] || die "Cannot determine OpenWrt subtarget from OPENWRT_BOARD"

if [ -z "$COPY_ONLY" ]; then
    need_cmd scp
fi

if [ -n "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || die "Cannot create output dir: $OUTPUT_DIR"
    OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)" || die "Cannot resolve output dir: $OUTPUT_DIR"
fi

SDK_URL="https://downloads.openwrt.org/releases/$VERSION/targets/$BOARD/"

echo "MODE:           $MODE"
echo "PACKAGE_NAME:   $PACKAGE_NAME"
echo "SELECTED:       $SELECTED_PACKAGES"
echo "BUILD_PACKAGES: $BUILD_PACKAGES"
echo "ROUTER:         ${ROUTER:-<none>}"
echo "VERSION:        $VERSION"
echo "BOARD:          $BOARD"
echo "TARGET:         $TARGET"
echo "SUBTARGET:      $SUBTARGET"
echo "BOARD_ARCH:     $BOARD_ARCH"
echo "SDK_URL:        $SDK_URL"
echo

SDK_HTML="$(curl -fsSL "$SDK_URL")" || die "Cannot read SDK directory: $SDK_URL"

SDK_ARCHIVE=$(
    printf '%s\n' "$SDK_HTML" \
        | sed -n 's/.*href="\([^"]*openwrt-sdk[^"]*\.tar\.\(xz\|zst\|gz\)\)".*/\1/p' \
        | head -n 1
)

[ -n "$SDK_ARCHIVE" ] || die "Cannot find SDK archive"

case "$SDK_ARCHIVE" in
    *.tar.zst)
        need_cmd zstd
        SDK_DIR="${SDK_ARCHIVE%.tar.zst}"
        ;;
    *.tar.xz)
        need_cmd xz
        SDK_DIR="${SDK_ARCHIVE%.tar.xz}"
        ;;
    *.tar.gz)
        need_cmd gzip
        SDK_DIR="${SDK_ARCHIVE%.tar.gz}"
        ;;
    *)
        die "Unsupported SDK archive format: $SDK_ARCHIVE"
        ;;
esac

if [ ! -f "$SDK_ARCHIVE" ]; then
    wget -q "$SDK_URL$SDK_ARCHIVE" \
        || die "Cannot download SDK archive: $SDK_ARCHIVE"
fi

if [ ! -d "$SDK_DIR" ]; then
    tar -xf "$SDK_ARCHIVE" \
        || die "Cannot extract SDK archive: $SDK_ARCHIVE"
fi

cd "$SDK_DIR" || die "Cannot enter SDK dir: $SDK_DIR"

if [ -f feeds.conf.default ]; then
    sed -i -E \
        's#https://git\.openwrt\.org/[^/]+/#https://github.com/openwrt/#g' \
        feeds.conf.default || die "Cannot rewrite feeds.conf.default"
fi

echo "Updating feeds"
./scripts/feeds update -a || die "feeds update failed"

echo "Installing feeds"
./scripts/feeds install -a || die "feeds install failed"

for pkg in $(prepare_package_list); do
    prepare_one_package "$pkg"
done

make defconfig || die "defconfig failed"

find_apk() {
    pkg="$1"

    find bin -type f \( \
        -name "${pkg}-*.apk" -o \
        -name "${pkg}_*.apk" \
        \) | sort | tail -n 1
}

release_apk_name() {
    pkg="$1"
    apk_path="$2"
    ext="${apk_path##*.}"

    printf '%s_v%s_%s_%s_%s.%s\n' \
        "$pkg" \
        "$VERSION" \
        "$BOARD_ARCH" \
        "$TARGET" \
        "$SUBTARGET" \
        "$ext"
}

install_or_copy_apk() {
    pkg="$1"
    apk_path="$2"
    apk_name="$(basename "$apk_path")"

    if [ -n "$COPY_ONLY" ]; then
        release_name="$(release_apk_name "$pkg" "$apk_path")"

        if [ -n "$OUTPUT_DIR" ]; then
            cp "$apk_path" "$OUTPUT_DIR/$release_name" \
                || die "Cannot save $release_name"
            echo "Saved: $OUTPUT_DIR/$release_name"
        else
            cp "$apk_path" "../$release_name" \
                || die "Cannot save $release_name"
            echo "Saved: ../$release_name"
        fi

        return
    fi

    remote_apk="/tmp/$apk_name"

    scp -O "$apk_path" "$ROUTER:$remote_apk" \
        || die "Cannot copy $apk_name to router"

    ssh "$ROUTER" sh -c 'apk del "$1" || true' sh "$pkg" \
        || die "Cannot remove old package on router: $pkg"

    ssh "$ROUTER" apk update \
        || die "apk update failed on router"

    ssh "$ROUTER" sh -c 'apk add --allow-untrusted "$1"' sh "$remote_apk" \
        || die "Cannot install package on router: $apk_name"

    ssh "$ROUTER" sh -c 'rm -f "$1"' sh "$remote_apk" \
        || die "Cannot remove temporary package from router: $apk_name"
}

for pkg in $BUILD_PACKAGES; do
    path="package/$pkg"
    output_pkg="$(output_package_name "$pkg")"

    echo
    echo "Building $pkg"
    echo

    make "$path/clean" || die "Clean failed: $pkg"

    if ! make -j"$(nproc)" "$path/compile"; then
        make -j1 V=s "$path/compile" || true
        die "Build failed: $pkg"
    fi

    apk_path="$(find_apk "$output_pkg")"

    [ -n "$apk_path" ] || die "APK not found for $output_pkg"
    [ -f "$apk_path" ] || die "APK not found for $output_pkg: $apk_path"

    install_or_copy_apk "$output_pkg" "$apk_path"

    printf '%sOK: %s%s\n' "$green" "$output_pkg" "$reset"
done

printf '%sAll done: %s%s\n' "$green" "$PACKAGE_NAME" "$reset"
