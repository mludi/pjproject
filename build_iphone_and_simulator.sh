#!/bin/sh
# Oliver Epper <oliver.epper@gmail.com>

#
# ask user if she wants to overwrite files
#

COMMAND_LINE_TOOLS_PATH="$(xcode-select -p)"

read -p "This will overwrite site_config.h and user.mak. Continue?" -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
   [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

cat << EOF > pjlib/include/pj/config_site.h
#define PJ_CONFIG_IPHONE 1
#define PJ_HAS_SSL_SOCK 1
#undef PJ_SSL_SOCK_IMP
#define PJ_SSL_SOCK_IMP PJ_SSL_SOCK_IMP_APPLE
#include <pj/config_site_sample.h>
EOF

cat << EOF > user.mak
export CFLAGS += -Wno-unused-label -Werror
export LDFLAGS += -framework Network -framework Security
EOF



#
# build for simulator arm64 & create lib
#
find . -not -path "./pjsip-apps/*" -not -path "./out/*" -name "*.a" -exec rm {} \;
IPHONESDK="$COMMAND_LINE_TOOLS_PATH/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk" DEVPATH="$COMMAND_LINE_TOOLS_PATH/Platforms/iPhoneSimulator.platform/Developer" ARCH="-arch arm64" MIN_IOS="-mios-simulator-version-min=13" ./configure-iphone
make dep && make clean
CFLAGS="-Wno-macro-redefined -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -Wno-unused-private-field" make

OUT_SIM_ARM64="out/sim_arm64"
mkdir -p $OUT_SIM_ARM64
# the Makefile is a little more selective about which .o files go into the lib
# so let's use libtool instead of ar
# ar -csr $OUT_SIM_ARM64/libpjproject.a `find . -not -path "./pjsip-apps/*" -name "*.o"`
libtool -static -o $OUT_SIM_ARM64/libpjproject.a `find . -not -path "./pjsip-apps/*" -not -path "./out/*" -name "*.a"`


#
# build for device arm64 & create lib
#
find . -not -path "./pjsip-apps/*" -not -path "./out/*" -name "*.a" -exec rm {} \;
IPHONESDK="$COMMAND_LINE_TOOLS_PATH/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk" DEVPATH="$COMMAND_LINE_TOOLS_PATH/Platforms/iPhoneOS.platform/Developer" ARCH="-arch arm64" MIN_IOS="-miphoneos-version-min=13" ./configure-iphone
make dep && make clean
CFLAGS="-Wno-macro-redefined -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -Wno-unused-private-field -fembed-bitcode" make

OUT_DEV_ARM64="out/dev_arm64"
mkdir -p $OUT_DEV_ARM64
libtool -static -o $OUT_DEV_ARM64/libpjproject.a `find . -not -path "./pjsip-apps/*" -not -path "./out/*" -name "*.a"`


#
# build for Mac arm64 & create lib
#
find . -not -path "./pjsip-apps/*" -not -path "./out/*" -name "*.a" -exec rm {} \;
sed -i '' '1d' pjlib/include/pj/config_site.h
./configure
make dep && make clean
CFLAGS="-Wno-macro-redefined -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -Wno-unused-private-field -fembed-bitcode" make

OUT_MAC_ARM64="out/mac_arm64"
mkdir -p $OUT_MAC_ARM64
libtool -static -o $OUT_MAC_ARM64/libpjproject.a `find . -not -path "./pjsip-apps/*" -not -path "./out/*" -name "*.a"`


#
# build for Mac x86_64 & create lib
#
cat << EOF > user.mak
export CFLAGS += -Wno-unused-label -Werror --target=x86_64-apple-darwin
export LDFLAGS += -framework Network -framework Security --target=x86_64-apple-darwin
EOF
find . -not -path "./pjsip-apps/*" -not -path "./out/*" -name "*.a" -exec rm {} \;
./configure --host=x86_64-apple-darwin20.6.0
make dep && make clean
CFLAGS="-Wno-macro-redefined -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -Wno-unused-private-field -fembed-bitcode" make

OUT_MAC_X86_64="out/mac_x86_64"
mkdir -p $OUT_MAC_X86_64
libtool -static -o $OUT_MAC_X86_64/libpjproject.a `find . -not -path "./pjsip-apps/*" -not -path "./out/*" -name "*.a"`


#
# create fat lib for the mac
#
OUT_MAC="out/mac"
mkdir -p $OUT_MAC
lipo -create $OUT_MAC_ARM64/libpjproject.a $OUT_MAC_X86_64/libpjproject.a -output $OUT_MAC/libpjproject.a



#
# collect headers & create xcframework
#
LIBS="pjlib pjlib-util pjmedia pjnath pjsip" # third_party"
OUT_HEADERS="out/headers"
for path in $LIBS; do
	mkdir -p $OUT_HEADERS/$path
	cp -a $path/include/* $OUT_HEADERS/$path
done

XCFRAMEWORK="out/libpjproject.xcframework"
rm -rf $XCFRAMEWORK
xcodebuild -create-xcframework \
-library $OUT_SIM_ARM64/libpjproject.a \
-library $OUT_DEV_ARM64/libpjproject.a \
-library $OUT_MAC/libpjproject.a \
-output $XCFRAMEWORK

mkdir -p $XCFRAMEWORK/Headers
cp -a $OUT_HEADERS/* $XCFRAMEWORK/Headers

/usr/libexec/PlistBuddy -c 'add:HeadersPath string Headers' $XCFRAMEWORK/Info.plist
