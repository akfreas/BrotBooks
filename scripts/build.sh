#!/bin/bash
# Build BrotBooks for macOS or the iOS Simulator.
#
#   scripts/build.sh mac            # ad-hoc signed, no iCloud entitlements: runs with the on-device store
#   scripts/build.sh mac --signed   # automatic signing with the team in Config/BrotBooks.xcconfig (needs Xcode account)
#   scripts/build.sh ios-sim        # iOS Simulator build (no signing needed)
#   scripts/build.sh test           # BrotBooksKit unit tests (swift test)
#
# The Xcode project is generated from project.yml with XcodeGen before every build.
# Products land in apple/build/<platform>/; the .app path is printed at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

target="${1:-mac}"
signed="${2:-}"
derived="build/DerivedData"

if [ "$target" != test ]; then
  command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen" >&2; exit 1; }
  xcodegen generate --spec project.yml --quiet
fi

case "$target" in
  test)
    (cd BrotBooksKit && swift test)
    ;;
  mac)
    args=(-project BrotBooks.xcodeproj -scheme BrotBooks -configuration Release
          -destination 'platform=macOS' -derivedDataPath "$derived")
    if [ "$signed" = "--signed" ]; then
      args+=(-allowProvisioningUpdates)
    else
      args+=(CODE_SIGN_ENTITLEMENTS=Config/BrotBooks-Local.entitlements CODE_SIGN_STYLE=Manual
             CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
    fi
    xcodebuild "${args[@]}" build
    mkdir -p build/mac
    rm -rf build/mac/BrotBooks.app
    cp -R "$derived/Build/Products/Release/BrotBooks.app" build/mac/
    echo "Built $(pwd)/build/mac/BrotBooks.app"
    ;;
  ios-sim)
    xcodebuild -project BrotBooks.xcodeproj -scheme BrotBooks -configuration Debug \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
      CODE_SIGN_ENTITLEMENTS=Config/BrotBooks-Local.entitlements build
    mkdir -p build/ios-sim
    rm -rf build/ios-sim/BrotBooks.app
    cp -R "$derived/Build/Products/Debug-iphonesimulator/BrotBooks.app" build/ios-sim/
    echo "Built $(pwd)/build/ios-sim/BrotBooks.app"
    ;;
  *)
    echo "usage: $0 mac [--signed] | ios-sim | test" >&2
    exit 2
    ;;
esac
