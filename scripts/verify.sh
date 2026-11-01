#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Match the Hygiene workflow and CI's lint, build, and test checks.
actionlint
zizmor --offline --min-severity medium .
scripts/install-ci-tools.sh
.build/ci-tools/bin/swiftlint lint --strict --quiet

xcodebuild -project TouchPoint.xcodeproj \
  -scheme TouchPoint \
  -configuration Debug \
  -derivedDataPath "$HOME/DerivedData/touchpoint-slot-0" \
  build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO

xcodebuild test -project TouchPoint.xcodeproj \
  -scheme TouchPoint \
  -destination 'platform=macOS' \
  -derivedDataPath "$HOME/DerivedData/touchpoint-slot-0" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
