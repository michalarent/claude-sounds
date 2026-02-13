#!/bin/bash
set -e

echo "Building Claude Sounds..."

rm -rf ClaudeSounds.app
mkdir -p ClaudeSounds.app/Contents/MacOS
cp Info.plist ClaudeSounds.app/Contents/
swiftc -O -o ClaudeSounds.app/Contents/MacOS/ClaudeSounds -framework Cocoa Sources/*.swift

echo "Built ClaudeSounds.app successfully."
echo "Run: open ClaudeSounds.app"
