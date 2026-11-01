#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

echo "=========================================="
echo " Building 极空BMS (JK-BMS) Native iOS App "
echo "=========================================="

python3 tools/generate_xcode_project.py

xcodebuild -project JKBMS.xcodeproj \
  -scheme JKBMS \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/derivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "=========================================="
echo " Build Succeeded! "
echo " Product: build/derivedData/Build/Products/Debug-iphonesimulator/JKBMS.app"
echo "=========================================="
