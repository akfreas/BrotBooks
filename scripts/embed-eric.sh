#!/bin/bash
# Xcode build phase of the BrotBooks target (see project.yml); does nothing outside macOS builds.
#
# Copies the Vendor/ERiC dylibs into Contents/Frameworks/ERiC (VERSION into Contents/Resources/ERiC) and signs
# every dylib with the app's identity and the hardened runtime. The shipped dylibs are only linker-signed and
# would fail library validation (and make dlopen hang); ad-hoc builds (CODE_SIGN_IDENTITY=-, scripts/build.sh
# mac) sign them ad hoc instead.
set -euo pipefail

[ "${PLATFORM_NAME:-}" = macosx ] || exit 0

src="$SRCROOT/Vendor/ERiC"
if [ ! -f "$src/libericapi.dylib" ] || [ ! -f "$src/inputs.xcfilelist" ]; then
  echo "error: Vendor/ERiC is missing. Run scripts/vendor-eric.sh <path-to-ERiC-jar> first." >&2
  exit 1
fi

identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "$identity" ] || [ "$identity" = "-" ]; then
  sign=(--sign - --timestamp=none)
else
  sign=(--sign "$identity" --timestamp)
fi

# Copy exactly the files in the input list: the script sandbox allows nothing else in the app bundle, not even
# codesign's temporary file next to the dylib, so each dylib is signed in TEMP_DIR (writable) and then copied in.
# VERSION goes to Contents/Resources/ERiC, since everything under Contents/Frameworks must be signed code.
# Xcode deletes outputs that are no longer listed after a re-vendor.
frameworks="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/ERiC"
resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/ERiC"
staging="$TEMP_DIR/EmbedERiC"
while IFS= read -r file; do
  relative="${file#\$(SRCROOT)/Vendor/ERiC/}"
  case "$relative" in
    *.dylib)
      mkdir -p "$(dirname "$staging/$relative")" "$(dirname "$frameworks/$relative")"
      cp -f "$src/$relative" "$staging/$relative"
      codesign --force --options runtime "${sign[@]}" "$staging/$relative"
      cp -f "$staging/$relative" "$frameworks/$relative"
      ;;
    *)
      mkdir -p "$(dirname "$resources/$relative")"
      cp -f "$src/$relative" "$resources/$relative"
      ;;
  esac
done < "$src/inputs.xcfilelist"
echo "Embedded ERiC $(cat "$resources/VERSION") in $frameworks (signed with ${identity:--})"
