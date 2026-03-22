#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
product_name="regionshot"
private_name="${PRIVATE_BINARY_NAME:-regionshot-private}"
install_dir="${INSTALL_DIR:-$project_dir/.build/private-bin}"
build_dir="$project_dir/.build/private-install"
target_path="$install_dir/$private_name"

identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(
    security find-identity -v -p codesigning |
      sed -n 's/.*"\(Apple Development:.*\)"/\1/p' |
      head -n 1
  )"
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

if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" "$target_path"
  echo "Signed with $identity"
else
  codesign --force --sign - "$target_path"
  echo "Signed ad-hoc"
fi

codesign --verify --verbose "$target_path"
echo "Private binary: $target_path"
