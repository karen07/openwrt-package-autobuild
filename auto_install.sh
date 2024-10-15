#!/bin/sh

if [ "$1" != "antiblock" ] && [ "$1" != "yubikey-hack" ] && [ "$1" != "dns-perftest" ] && [ "$1" != "url-block-test" ]; then
	echo "Argument 1: Invalid package name"
	echo "Use antiblock or yubikey-hack or dns-perftest or url-block-test"
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

if [ ! -f "package/$PACKAGE_NAME" ]; then
	if ! git clone --recursive git@github.com:karen07/$PACKAGE_NAME.git package/$PACKAGE_NAME; then
		git clone --recursive https://github.com/karen07/$PACKAGE_NAME.git package/$PACKAGE_NAME
	fi
fi

if [ ! -f "package/$PACKAGE_NAME-openwrt-package" ]; then
	if ! git clone --recursive git@github.com:karen07/$PACKAGE_NAME-openwrt-package.git package/$PACKAGE_NAME-openwrt-package; then
		git clone --recursive https://github.com/karen07/$PACKAGE_NAME-openwrt-package.git package/$PACKAGE_NAME-openwrt-package
	fi
fi

cat >auto.sh <<EOF
#!/bin/sh

make defconfig

PACKAGE_SRC_FOLDER=package
PACKAGE=$PACKAGE_NAME
ROUTER_NAME=$ROUTER_NAME

PACKAGE_SRC_NAME=\$(ls \$PACKAGE_SRC_FOLDER | grep -i \$PACKAGE | grep -i package)
PACKAGE_SRC_PATH=\$PACKAGE_SRC_FOLDER/\$PACKAGE_SRC_NAME

make \$PACKAGE_SRC_PATH/clean

if make \$PACKAGE_SRC_PATH/compile; then

	PACKAGE_PATH=\$(find bin | grep \$PACKAGE)
	PACKAGE_NAME=\$(basename \$PACKAGE_PATH)

	if [ -f "\$PACKAGE_PATH" ]; then
		scp -O \$PACKAGE_PATH \$ROUTER_NAME:~/
		ssh \$ROUTER_NAME opkg remove \$PACKAGE
		ssh \$ROUTER_NAME opkg install \$PACKAGE_NAME
		ssh \$ROUTER_NAME rm \$PACKAGE_NAME
		echo "Command succeeded"
	fi
else
	make -j1 V=s \$PACKAGE_SRC_PATH/compile
	echo "Command failed"
fi
EOF
chmod +x auto.sh

./auto.sh
