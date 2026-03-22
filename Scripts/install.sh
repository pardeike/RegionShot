#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
product_name="regionshot"
install_dir="${INSTALL_DIR:-$HOME/Scripts}"
build_dir="$project_dir/.build/install"
target_path="$install_dir/$product_name"

identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(
    security find-identity -v -p codesigning |
      sed -n 's/.*"\(Apple Development:.*\)"/\1/p' |
      head -n 1
  )"
fi

if [[ -z "$identity" ]]; then
  echo "No Apple Development signing identity found. Set CODESIGN_IDENTITY to override." >&2
  exit 1
fi

mkdir -p "$install_dir"

swift build \
  --package-path "$project_dir" \
  --configuration release \
  --product "$product_name" \
  --build-path "$build_dir"

/usr/bin/install -m 755 "$build_dir/release/$product_name" "$target_path"
if [[ ! -f "$target_path" ]]; then
  echo "Failed to install $product_name to $target_path" >&2
  exit 1
fi
codesign --force --sign "$identity" "$target_path"
codesign --verify --verbose "$target_path"

echo "Installed $product_name to $target_path"
echo "Signed with $identity"
