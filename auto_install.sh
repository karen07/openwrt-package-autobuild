#!/bin/sh

if [ "$1" != "antiblock" ] && [ "$1" != "yubikey-hack" ]; then
	echo "Invalid package name"
	echo "Use antiblock or yubikey-hack"
	exit 1
fi

PACKAGE_NAME=$1

SDK="https://mirror-03.infra.openwrt.org/releases/23.05.3/targets/mediatek/filogic/openwrt-sdk-23.05.3-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
ARCHIVE=$(basename $SDK)

if [ ! -f "$ARCHIVE" ]; then
	wget $SDK
fi

FOLDER=$(echo $ARCHIVE | rev | cut -c 8- | rev)

if [ ! -f "$FOLDER" ]; then
	tar -xf $ARCHIVE
fi

cd $FOLDER/

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
