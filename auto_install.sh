#!/bin/sh

if [ "$1" != "antiblock" ] && [ "$1" != "yubikey-hack" ]; then
	echo "Invalid package name"
	echo "Use antiblock or yubikey-hack"
	exit 1
fi

PACKAGE_NAME=$1

ROUTER_OS_RELEASE="$(ssh router cat /etc/os-release)"
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

if [ ! -f "package/$PACKAGE_NAME" ]; then
	git clone --recursive git@github.com:karen07/$PACKAGE_NAME.git package/$PACKAGE_NAME
fi

if [ ! -f "package/$PACKAGE_NAME-openwrt-package" ]; then
	git clone --recursive git@github.com:karen07/$PACKAGE_NAME-openwrt-package.git package/$PACKAGE_NAME-openwrt-package
fi

cat >auto.sh <<EOF
#!/bin/sh

make defconfig

PACKAGE_SRC_FOLDER=package
PACKAGE=$PACKAGE_NAME

PACKAGE_SRC_NAME=\$(ls \$PACKAGE_SRC_FOLDER | grep -i \$PACKAGE | grep -i package)
PACKAGE_SRC_PATH=\$PACKAGE_SRC_FOLDER/\$PACKAGE_SRC_NAME

make \$PACKAGE_SRC_PATH/clean

if make \$PACKAGE_SRC_PATH/compile; then

	PACKAGE_PATH=\$(find bin | grep \$PACKAGE)
	PACKAGE_NAME=\$(basename \$PACKAGE_PATH)

	if [ -f "\$PACKAGE_PATH" ]; then
		scp -O \$PACKAGE_PATH router:~/
		ssh router opkg remove \$PACKAGE
		ssh router opkg install \$PACKAGE_NAME
		ssh router rm \$PACKAGE_NAME
		echo "Command succeeded"
	fi
else
	make -j1 V=s \$PACKAGE_SRC_PATH/compile
	echo "Command failed"
fi
EOF
chmod +x auto.sh

./auto.sh
