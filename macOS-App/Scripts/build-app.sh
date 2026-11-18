#!/bin/zsh
# Baut Riftsight.app mit SwiftPM (nur Command Line Tools erforderlich, kein Xcode).
# Aufruf aus beliebigem Verzeichnis: ./Scripts/build-app.sh [Zielpfad/Riftsight.app]
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Riftsight"
BUNDLE_ID="de.riftsight.app"
VERSION="${RIFTSIGHT_VERSION:-1.0.0}"
BUILD_NUMBER="${RIFTSIGHT_BUILD_NUMBER:-1}"

TARGET_ARG="${1:-.build/${APP_NAME}.app}"
if [[ "$TARGET_ARG" == *.app ]]; then
  APP_BUNDLE="$TARGET_ARG"
else
  APP_BUNDLE="${TARGET_ARG%/}/${APP_NAME}.app"
fi

CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> [1/4] Kompiliere ${APP_NAME} (Release) via SwiftPM …"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY_PATH="${BIN_DIR}/${APP_NAME}"

if [[ ! -f "$BINARY_PATH" ]]; then
  echo "Fehler: Kompilierte Binary nicht gefunden unter ${BINARY_PATH}" >&2
  exit 1
fi

echo "==> [2/4] Erzeuge App-Bundle unter ${APP_BUNDLE} …"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY_PATH" "${MACOS_DIR}/${APP_NAME}"
chmod 755 "${MACOS_DIR}/${APP_NAME}"

if [[ -d "Resources/SampleData" ]]; then
  cp -R "Resources/SampleData" "${RESOURCES_DIR}/SampleData"
else
  echo "Fehler: Resources/SampleData wurde nicht gefunden." >&2
  exit 1
fi

printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"

echo "==> [3/4] Schreibe Info.plist (Bundle-ID: ${BUNDLE_ID}) …"
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>de</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Riftsight benötigt Zugriff auf die Bildschirmaufnahme, um deine League-of-Legends-Spiele lokal als Replay aufzuzeichnen und angebotene Augments im Spiel zu erkennen.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Riftsight verbindet sich lokal mit dem laufenden League-of-Legends-Client (127.0.0.1), um Champ-Select-, Live-Spiel- und Post-Game-Daten anzuzeigen.</string>
</dict>
</plist>
EOF

plutil -lint "${CONTENTS_DIR}/Info.plist" >/dev/null

echo "==> [4/4] Signiere ${APP_BUNDLE} (ad-hoc codesign) …"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> Fertig: ${APP_BUNDLE}"
