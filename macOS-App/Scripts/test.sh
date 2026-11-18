#!/bin/zsh
# Runs the Swift Testing suite. With only the Command Line Tools installed (no Xcode),
# SwiftPM does not find the Testing macro plugin and runtime on its own, so we pass the paths.
set -e
cd "$(dirname "$0")/.."
DEV="$(xcode-select -p)"
if [[ "$DEV" == *CommandLineTools* ]]; then
  swift test \
    -Xswiftc -plugin-path -Xswiftc "$DEV/usr/lib/swift/host/plugins/testing" \
    -Xlinker -rpath -Xlinker "$DEV/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$DEV/Library/Developer/usr/lib" "$@"
else
  swift test "$@"
fi
