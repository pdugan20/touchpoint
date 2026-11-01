#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

readonly version=0.65.1
readonly sha256=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
readonly bin_dir="$PWD/.build/ci-tools/bin"
mkdir -p "$bin_dir"
download_dir=$(mktemp -d "$PWD/.build/ci-tools/download.XXXXXX")
trap 'rm -rf "$download_dir"' EXIT

curl --fail --location --silent --show-error \
  "https://github.com/realm/SwiftLint/releases/download/$version/portable_swiftlint.zip" \
  -o "$download_dir/swiftlint.zip"
printf '%s  %s\n' "$sha256" "$download_dir/swiftlint.zip" | shasum -a 256 --check
unzip -q "$download_dir/swiftlint.zip" swiftlint -d "$download_dir"
install -m 755 "$download_dir/swiftlint" "$bin_dir/swiftlint"
"$bin_dir/swiftlint" version
