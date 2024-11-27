#!/bin/sh

if [ "$1" != "antiblock" ] && [ "$1" != "yubikey-hack" ] && [ "$1" != "dns-perf-test" ] && [ "$1" != "url-block-test" ] && [ "$1" != "dns-server-test" ] && [ "$1" != "luci-app-antiblock" ]; then
	echo "Argument 1: Invalid package name"
	echo "Use antiblock or yubikey-hack or dns-perf-test or url-block-test or dns-server-test or luci-app-antiblock"
	exit 1
fi

if [ -z "$2" ]; then
	echo "Argument 2: Empty router ssh name"
	exit 1
fi

if [ -f /usr/bin/apt ]; then
	sudo apt update && sudo apt-get install -y make unzip bzip2 build-essential libncurses5-dev libncursesw5-dev
fi

if [ -f /usr/bin/pacman ]; then
	sudo pacman -S make wget rsync base-devel unzip python3 python-distutils-extra --noconfirm
fi

PACKAGE_NAME=$1
ROUTER_NAME=$2

if ! ssh -o StrictHostKeyChecking=no $ROUTER_NAME cat /etc/os-release; then
	echo "SSH connection or remote command failed"
	exit 1
fi

ROUTER_OS_RELEASE="$(ssh $ROUTER_NAME cat /etc/os-release)"
VERSION=$(echo "$ROUTER_OS_RELEASE" | grep VERSION | head -n 1 | sed -r 's/.*"([^"]+).*/\1/g')
BOARD=$(echo "$ROUTER_OS_RELEASE" | grep OPENWRT_BOARD | head -n 1 | sed -r 's/.*"([^"]+).*/\1/g')
SDK_WEB_FOLDER="https://downloads.openwrt.org/releases/$VERSION/targets/$BOARD/"
SDK_ARCHIVE=$(curl -s $SDK_WEB_FOLDER | grep -i sdk | sed -r 's/.*href="([^"]+).*/\1/g')

if [ ! -f "$SDK_ARCHIVE" ]; then
	wget $SDK_WEB_FOLDER$SDK_ARCHIVE
fi

SDK_FOLDER=$(echo $SDK_ARCHIVE | rev | cut -c 8- | rev)

if [ ! -f "$SDK_FOLDER" ]; then
	tar -xf $SDK_ARCHIVE
fi

cd $SDK_FOLDER/

./scripts/feeds update -a
./scripts/feeds install -a

ssh -o StrictHostKeyChecking=no git@github.com

if [ "$PACKAGE_NAME" != "luci-app-antiblock" ]; then
	if [ ! -f "package/$PACKAGE_NAME" ]; then
		if ! git clone --recursive git@github.com:karen07/$PACKAGE_NAME.git package/$PACKAGE_NAME; then
			git clone --recursive https://github.com/karen07/$PACKAGE_NAME.git package/$PACKAGE_NAME
		fi
	fi
fi

PACKAGE_BUILD_NAME=$PACKAGE_NAME-openwrt-package

if [ ! -f "package/$PACKAGE_BUILD_NAME" ]; then
	if ! git clone --recursive git@github.com:karen07/$PACKAGE_BUILD_NAME.git package/$PACKAGE_BUILD_NAME; then
		git clone --recursive https://github.com/karen07/$PACKAGE_BUILD_NAME.git package/$PACKAGE_BUILD_NAME
	fi
fi

cat >auto.sh <<EOF
#!/bin/sh

echo "Building $PACKAGE_BUILD_NAME"
echo ""

make defconfig
make package/$PACKAGE_BUILD_NAME/clean

if make -j$(nproc) package/$PACKAGE_BUILD_NAME/compile; then

	PACKAGE_IPK_PATH=\$(find bin | grep "/${PACKAGE_NAME}_")
	PACKAGE_IPK_NAME=\$(basename \$PACKAGE_IPK_PATH)

	if [ -f "\$PACKAGE_IPK_PATH" ]; then
		scp -O \$PACKAGE_IPK_PATH $ROUTER_NAME:~/
		ssh $ROUTER_NAME opkg remove --force-depends $PACKAGE_NAME
		ssh $ROUTER_NAME opkg update
		ssh $ROUTER_NAME opkg install \$PACKAGE_IPK_NAME
		ssh $ROUTER_NAME rm \$PACKAGE_IPK_NAME
		echo "Command succeeded"
	fi
else
	make -j1 V=s package/$PACKAGE_BUILD_NAME/compile
	echo "Command failed"
fi
EOF
chmod +x auto.sh

./auto.sh
