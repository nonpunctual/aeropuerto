#!/bin/sh
# Rebuilds aeropuerto and refreshes the aeropuerto.app bundle wrapper.
#
# The bundle wrapper (rather than the bare .build/debug/aeropuerto executable) is what's
# actually required: Location Services' consent prompt only resolves for a properly signed
# Application bundle with a real Team ID, not a bare ad-hoc-signed Mach-O binary.
#
# This script only builds the dev .app bundle. To build the signed, notarized, distributable
# .pkg (for a GitHub release), run /Users/Shared/scripty-legacy/build.pkg.sh --distribution
# against this project's distribution.xml/payload/Resources/Scripts/component-plist.plist,
# with notarization-profile "com.nonpunctual.aeropuerto" (the keychain profile stored via
# `xcrun notarytool store-credentials com.nonpunctual.aeropuerto --apple-id ... --team-id ...`).

cd "$(dirname "$0")" || exit 1

signing_identity="0CD92A821C2612EB2C41B8619E8FA9B59B36DBD6"
bundle_plist="aeropuerto.app/Contents/Info.plist"

if ! swift build
then
    echo "build.sh: swift build failed" >&2; exit 1
fi

rm -rf aeropuerto.app
mkdir -p aeropuerto.app/Contents/MacOS

if ! cp .build/debug/aeropuerto aeropuerto.app/Contents/MacOS/aeropuerto
then
    echo "build.sh: failed to copy binary into bundle" >&2; exit 1
fi

plist_add() {
    key="$1"; type="$2"; value="$3"
    if ! /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$bundle_plist"
    then
        echo "build.sh: failed to set $key in $bundle_plist" >&2; exit 1
    fi
}

cat > "$bundle_plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EOF

plist_add CFBundleExecutable string aeropuerto
plist_add CFBundleName string aeropuerto
plist_add CFBundlePackageType string APPL
plist_add LSMinimumSystemVersion string 12.0
plist_add LSUIElement bool true

# Everything identity/version/usage-description related is sourced from
# Sources/aeropuerto/Info.plist, the one tracked source of truth, so the bundle
# Info.plist (what TCC/Launch Services actually read) can never drift from it -
# it's fully regenerated here on every build instead of hand-patched.
for key in CFBundleIdentifier CFBundleVersion CFBundleShortVersionString NSLocationUsageDescription NSLocationWhenInUseUsageDescription
do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" Sources/aeropuerto/Info.plist)"
    if [ $? -ne 0 ]
    then
        echo "build.sh: failed to read $key from Sources/aeropuerto/Info.plist" >&2; exit 1
    fi
    plist_add "$key" string "$value"
done

if ! codesign --force --deep --options runtime --timestamp --sign "$signing_identity" aeropuerto.app
then
    echo "build.sh: codesign failed" >&2; exit 1
fi

/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$(pwd)/aeropuerto.app"

echo "build.sh: syncing payload copy for packaging..."
rm -rf payload/Applications/Utilities/aeropuerto.app
mkdir -p payload/Applications/Utilities
cp -R aeropuerto.app payload/Applications/Utilities/aeropuerto.app

echo "build.sh: done. Run with:"
echo "  $(pwd)/aeropuerto.app/Contents/MacOS/aeropuerto"