#!/bin/sh
# Builds a universal build/Atbang.app and zips it as build/Atbang-$VERSION.zip.
# VERSION defaults to 0.1.0. SIGN_IDENTITY signs with that Developer ID certificate instead of an ad-hoc
# signature, and NOTARY_PROFILE, a profile saved with `xcrun notarytool store-credentials`, notarizes and staples.
set -eu

cd "$(dirname "$0")/.."
VERSION=${VERSION:-0.1.0}
swift build -c release --arch arm64 --arch x86_64
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

app=build/Atbang.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/Atbang" "$app/Contents/MacOS/Atbang"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Atbang</string>
    <key>CFBundleExecutable</key>
    <string>Atbang</string>
    <key>CFBundleIdentifier</key>
    <string>dev.daubois.Atbang</string>
    <key>CFBundleName</key>
    <string>Atbang</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"

zip=build/Atbang-$VERSION.zip
rm -f "$zip"
ditto -c -k --norsrc --noextattr --noacl --keepParent "$app" "$zip"
if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    rm -f "$zip"
    ditto -c -k --norsrc --noextattr --noacl --keepParent "$app" "$zip"
fi
# The checksum a Homebrew cask pins for this zip.
shasum -a 256 "$zip"
