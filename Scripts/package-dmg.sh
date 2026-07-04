#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
product_name="regionshot"
version="${VERSION:-}"
output_root="${OUTPUT_ROOT:-$project_dir/output/release}"
build_dir="$project_dir/.build/release-dmg"
notary_profile="${NOTARY_KEYCHAIN_PROFILE:-brrainz-notary}"
notarize="${NOTARIZE:-1}"

if [[ -z "$version" ]]; then
  version="$(git -C "$project_dir" describe --tags --always --dirty)"
fi

safe_version="$(printf '%s' "$version" | tr -c 'A-Za-z0-9._-' '-')"
release_dir="$output_root/RegionShot-$safe_version"
staging_dir="$release_dir/staging"
payload_dir="$staging_dir/RegionShot"
dmg_path="$release_dir/RegionShot-$safe_version-macos.dmg"

identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(
    security find-identity -v -p codesigning |
      sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
      head -n 1
  )"
fi

if [[ -z "$identity" ]]; then
  echo "Missing Developer ID Application signing identity." >&2
  echo "Set CODESIGN_IDENTITY or install a Developer ID Application certificate." >&2
  exit 1
fi

rm -rf "$release_dir"
mkdir -p "$payload_dir/.regionshot-support"
printf '%s\n' "$version" > "$payload_dir/.regionshot-support/VERSION"

swift build \
  --package-path "$project_dir" \
  --configuration release \
  --product "$product_name" \
  --build-path "$build_dir"

/usr/bin/install -m 755 "$build_dir/release/$product_name" "$payload_dir/$product_name"
ditto "$project_dir/Codex" "$payload_dir/.regionshot-support/Codex"
/usr/bin/install -m 644 "$project_dir/README.md" "$payload_dir/README.md"
if [[ -d "$project_dir/docs" ]]; then
  ditto "$project_dir/docs" "$payload_dir/docs"
fi

cat > "$payload_dir/Install RegionShot.command" <<'INSTALL_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install_dir="${INSTALL_DIR:-$HOME/Scripts}"
support_root="$install_dir/.regionshot-support"

mkdir -p "$install_dir" "$support_root"
/usr/bin/install -m 755 "$source_dir/regionshot" "$install_dir/regionshot"
rm -rf "$support_root/Codex"
ditto "$source_dir/.regionshot-support/Codex" "$support_root/Codex"
if [[ -f "$source_dir/.regionshot-support/VERSION" ]]; then
  /usr/bin/install -m 644 "$source_dir/.regionshot-support/VERSION" "$support_root/VERSION"
fi

echo "Installed regionshot to $install_dir/regionshot"
echo "Installed Codex support files to $support_root/Codex"
echo
echo "If needed, add this to ~/.zprofile:"
echo "export PATH=\"\$HOME/Scripts:\$PATH\""
INSTALL_SCRIPT
chmod 755 "$payload_dir/Install RegionShot.command"

codesign \
  --force \
  --timestamp \
  --options runtime \
  --sign "$identity" \
  "$payload_dir/$product_name"
codesign --verify --verbose "$payload_dir/$product_name"
spctl --assess --type execute --verbose "$payload_dir/$product_name" || true

hdiutil create \
  -volname "RegionShot $version" \
  -srcfolder "$payload_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

codesign \
  --force \
  --timestamp \
  --sign "$identity" \
  "$dmg_path"
codesign --verify --verbose "$dmg_path"

if [[ "$notarize" == "1" ]]; then
  xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$notary_profile" \
    --wait
  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$dmg_path"
  spctl --assess --type open --context context:primary-signature --verbose "$dmg_path"
else
  echo "Skipping notarization because NOTARIZE=$notarize"
fi

shasum -a 256 "$dmg_path" | tee "$dmg_path.sha256"
echo "Release DMG: $dmg_path"
