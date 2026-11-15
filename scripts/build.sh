#!/bin/zsh
# Builds Glose with swiftc directly (SwiftPM in the installed Command Line Tools cannot link manifests).
#   scripts/build.sh            → build/Glose.app
#   scripts/build.sh --install  → also copies it to /Applications
#   scripts/build.sh --test     → builds and runs the GloseCore tests only
set -euo pipefail
cd "${0:A:h}/.."
OUT=build
TARGET=arm64-apple-macos15.0
mkdir -p $OUT
# A stale 2023 module.modulemap left by an older CLT install redefines SwiftBridging;
# hide it from the compiler instead of deleting a system file.
sed "s#@EMPTY@#$PWD/scripts/toolchain-fix/empty.modulemap#" scripts/toolchain-fix/overlay.yaml.in > $OUT/overlay.yaml
FLAGS=(-target $TARGET -swift-version 5 -O -vfsoverlay $OUT/overlay.yaml -Xcc -ivfsoverlay -Xcc $OUT/overlay.yaml)

swiftc $FLAGS -parse-as-library -emit-library -static -module-name GloseCore \
  -emit-module -emit-module-path $OUT/GloseCore.swiftmodule \
  -o $OUT/libGloseCore.a Sources/GloseCore/*.swift

if [[ "${1:-}" == "--test" ]]; then
  swiftc $FLAGS -I $OUT -L $OUT -lGloseCore -o $OUT/core-tests Tests/*.swift
  exec $OUT/core-tests
fi

swiftc $FLAGS -parse-as-library -I $OUT -L $OUT -lGloseCore -o $OUT/Glose Sources/Glose/*.swift

APP=$OUT/Glose.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp $OUT/Glose $APP/Contents/MacOS/Glose
cp Resources/Info.plist $APP/Contents/Info.plist
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns $APP/Contents/Resources/
codesign --force --sign - $APP
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Glose.app
  cp -R $APP /Applications/Glose.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Glose.app
  echo "installed /Applications/Glose.app"
fi
