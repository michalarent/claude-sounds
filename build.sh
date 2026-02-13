#!/bin/bash
set -e

echo "Building Claude Sounds..."

rm -rf ClaudeSounds.app
mkdir -p ClaudeSounds.app/Contents/MacOS
cp Info.plist ClaudeSounds.app/Contents/
swiftc -O -o ClaudeSounds.app/Contents/MacOS/ClaudeSounds -framework Cocoa -framework AVFoundation -framework SwiftUI Sources/*.swift
codesign --force --deep --sign - ClaudeSounds.app

echo "Built ClaudeSounds.app successfully."
echo "Run: open ClaudeSounds.app"
