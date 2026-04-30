#!/bin/bash
# Script to build a .deb package for Inatel Runner

PACKAGE_NAME="inatel-runner"
VERSION="1.0"
ARCH="amd64"
BUILD_DIR="deb_build"

# Clean previous builds
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR/opt/InatelRunner
mkdir -p $BUILD_DIR/usr/share/applications
mkdir -p $BUILD_DIR/DEBIAN

# Copy game files
cp ../builds/linux/InatelRunner.x86_64 $BUILD_DIR/opt/InatelRunner/InatelRunner
chmod +x $BUILD_DIR/opt/InatelRunner/InatelRunner

# Create Control file
cat <<EOF > $BUILD_DIR/DEBIAN/control
Package: $PACKAGE_NAME
Version: $VERSION
Section: games
Priority: optional
Architecture: $ARCH
Maintainer: Inatel <contato@inatel.br>
Description: Endless runner game with AI head tracking.
 Developed for Inatel.
EOF

# Create Desktop Entry
cat <<EOF > $BUILD_DIR/usr/share/applications/inatel-runner.desktop
[Desktop Entry]
Name=Inatel Runner
Exec=/opt/InatelRunner/InatelRunner
Icon=games
Terminal=false
Type=Application
Categories=Game;
EOF

# Build package
mkdir -p ../builds/installer
dpkg-deb --build $BUILD_DIR ../builds/installer/InatelRunner_Linux.deb

echo "Pacote .deb gerado com sucesso em builds/installer/"
