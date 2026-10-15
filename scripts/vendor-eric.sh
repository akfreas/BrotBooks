#!/bin/bash
# Vendor the ERiC libraries BrotBooks needs from the ELSTER SDK jar.
#
#   scripts/vendor-eric.sh ERiC-44.3.6.0-Darwin-universal.jar
#
# Copies the base libraries (libericapi, libericxerces, libeSigner) and the plugins libcommonData,
# libcheckZMDO and libcheckUStVA_<year> into Vendor/ERiC/ (gitignored), and the C headers into
# EricKit/Sources/CEric/include/eric/ (committed). Only the newest UStVA plugin is taken unless
# ERIC_USTVA_YEARS lists the years to keep, e.g. ERIC_USTVA_YEARS="2025 2026".
#
# The shipped dylibs are only linker-signed: dlopen hangs on them until they are re-signed, so every
# copy is re-signed ad hoc here (for swift test). The app build phase signs them again with the app identity.
# Safe to run again: Vendor/ERiC and the headers are replaced as a whole.
set -euo pipefail
cd "$(dirname "$0")/.."

jar="${1:-}"
if [ -z "$jar" ] || [ ! -f "$jar" ]; then
  echo "usage: $0 <path-to-ERiC-<version>-Darwin-universal.jar>" >&2
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The jar is a zip whose single top-level folder is ERiC-<version>/Darwin-universal/.
root="$(unzip -Z1 "$jar" | grep -m1 -E '^ERiC-[0-9.]+/Darwin-universal/lib/libericapi\.dylib$' | cut -d/ -f1-2)" || true
if [ -z "$root" ]; then
  echo "error: $jar does not contain ERiC-<version>/Darwin-universal/lib/libericapi.dylib" >&2
  exit 1
fi
version="${root%%/*}"
version="${version#ERiC-}"

if [ -n "${ERIC_USTVA_YEARS:-}" ]; then
  years="$ERIC_USTVA_YEARS"
else
  years="$(unzip -Z1 "$jar" "$root/lib/plugins/libcheckUStVA_*.dylib" \
    | sed -E 's/.*libcheckUStVA_([0-9]{4})\.dylib$/\1/' | sort -n | tail -1)"
fi

patterns=(
  "$root/lib/libericapi.dylib" "$root/lib/libericxerces.dylib" "$root/lib/libeSigner.dylib"
  "$root/lib/plugins/libcommonData.dylib" "$root/lib/plugins/libcheckZMDO.dylib"
  "$root/include/*.h"
)
for year in $years; do patterns+=("$root/lib/plugins/libcheckUStVA_$year.dylib"); done

echo "Extracting ERiC $version (UStVA plugins: $years)"
unzip -q -o "$jar" "${patterns[@]}" -d "$tmp"
src="$tmp/$root"
for year in $years; do
  [ -f "$src/lib/plugins/libcheckUStVA_$year.dylib" ] || { echo "error: no UStVA plugin for $year in $jar" >&2; exit 1; }
done

dest="Vendor/ERiC"
rm -rf "$dest"
mkdir -p "$dest/plugins"
cp "$src/lib/libericapi.dylib" "$src/lib/libericxerces.dylib" "$src/lib/libeSigner.dylib" "$dest/"
cp "$src/lib/plugins/"*.dylib "$dest/plugins/"
echo "$version" > "$dest/VERSION"

# The app's Embed ERiC build phase runs in Xcode's script sandbox, which only allows the files it declares.
# These lists (not themselves embedded) name what it copies and produces.
(cd "$dest" && find . -type f \( -name '*.dylib' -o -name VERSION \) | sed 's|^\./||' | sort) > "$tmp/files"
sed 's|^|$(SRCROOT)/Vendor/ERiC/|' "$tmp/files" > "$dest/inputs.xcfilelist"
# VERSION goes to Contents/Resources: every file under Contents/Frameworks must be signed code.
sed -e 's|^VERSION$|$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/ERiC/VERSION|' \
    -e 's|^\([^$].*\.dylib\)$|$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/ERiC/\1|' "$tmp/files" > "$dest/outputs.xcfilelist"

xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
find "$dest" -name '*.dylib' -print0 | xargs -0 codesign --force --sign - --timestamp=none

headers="EricKit/Sources/CEric/include/eric"
rm -rf "$headers"
mkdir -p "$headers"
cp "$src/include/"*.h "$headers/"
xattr -dr com.apple.quarantine "$headers" 2>/dev/null || true

echo "Vendored ERiC $version into $dest ($(du -sh "$dest" | cut -f1)) and headers into $headers"
