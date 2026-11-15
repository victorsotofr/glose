#!/bin/zsh
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
sed "s#@EMPTY@#$PWD/scripts/toolchain-fix/empty.modulemap#" scripts/toolchain-fix/overlay.yaml.in > build/overlay.yaml
swiftc -vfsoverlay build/overlay.yaml -Xcc -ivfsoverlay -Xcc build/overlay.yaml -o build/make-icon scripts/make-icon.swift
rm -rf build/AppIcon.iconset
build/make-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"
