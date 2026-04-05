#!/usr/bin/env bash
# build-dmg.sh — Build a release .dmg for ThoughtSnap
#
# Prerequisites:
#   brew install create-dmg
#   Xcode 15+ with a valid Developer ID Application certificate
#   (or run with SKIP_SIGNING=1 for ad-hoc local builds)
#
# Usage:
#   ./Scripts/build-dmg.sh                    # full signed + notarized build
#   SKIP_SIGNING=1 ./Scripts/build-dmg.sh     # local unsigned build

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
APP_NAME="ThoughtSnap"
VERSION="0.1.0"
SCHEME="ThoughtSnap"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
EXPORT_OPTIONS="Resources/ExportOptions.plist"
SKIP_SIGNING="${SKIP_SIGNING:-0}"

# ── Helpers ───────────────────────────────────────────────────────────────────
info()  { echo "▶ $*"; }
ok()    { echo "✅ $*"; }
fail()  { echo "❌ $*" >&2; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────
command -v xcodebuild >/dev/null || fail "xcodebuild not found — install Xcode"
command -v create-dmg >/dev/null || fail "create-dmg not found — run: brew install create-dmg"

mkdir -p "$BUILD_DIR"

# ── Archive ───────────────────────────────────────────────────────────────────
info "Archiving $SCHEME…"
if [ "$SKIP_SIGNING" = "1" ]; then
    xcodebuild archive \
        -scheme "$SCHEME" \
        -archivePath "$ARCHIVE_PATH" \
        -configuration Release \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO
else
    xcodebuild archive \
        -scheme "$SCHEME" \
        -archivePath "$ARCHIVE_PATH" \
        -configuration Release \
        CODE_SIGN_STYLE=Automatic
fi
ok "Archive complete: $ARCHIVE_PATH"

# ── Export ────────────────────────────────────────────────────────────────────
info "Exporting app bundle…"
if [ "$SKIP_SIGNING" = "1" ]; then
    # Extract .app directly from the archive for unsigned builds
    mkdir -p "$EXPORT_PATH"
    cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_PATH/"
else
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        -exportPath "$EXPORT_PATH"

    # Notarize (only if credentials are available)
    APP_PATH="$EXPORT_PATH/$APP_NAME.app"
    if xcrun notarytool history --keychain-profile "AC_PASSWORD" &>/dev/null; then
        info "Notarizing…"
        xcrun notarytool submit "$APP_PATH" \
            --keychain-profile "AC_PASSWORD" \
            --wait
        xcrun stapler staple "$APP_PATH"
        ok "Notarization and stapling complete"
    else
        echo "⚠️  Skipping notarization — 'AC_PASSWORD' keychain profile not found"
        echo "   Run: xcrun notarytool store-credentials AC_PASSWORD --apple-id you@example.com"
    fi
fi
ok "Export complete: $EXPORT_PATH/$APP_NAME.app"

# ── DMG ───────────────────────────────────────────────────────────────────────
info "Building DMG…"
rm -f "$DMG_PATH"

create-dmg \
    --volname "$APP_NAME $VERSION" \
    --volicon "Resources/Assets.xcassets/AppIcon.appiconset" \
    --window-size 580 380 \
    --icon-size 120 \
    --icon "$APP_NAME.app" 160 180 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 420 180 \
    --background-color "1A1A1A" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$EXPORT_PATH/$APP_NAME.app" \
|| {
    # create-dmg returns exit code 2 when no code signing is available — treat as warning
    echo "⚠️  create-dmg exited with warnings (likely unsigned DMG) — continuing"
}

ok "DMG built: $DMG_PATH"
ls -lh "$DMG_PATH"
