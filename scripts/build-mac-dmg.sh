#!/bin/bash
# Builds the drag-to-install DMG: app on the left, Applications on the right,
# over the background in design/dmg (regenerate it with design/dmg/render-background.swift).
set -euo pipefail
if [[ $# -ne 2 ]]; then
    echo 'Usage: build-mac-dmg.sh /path/iMDReader.app /path/new-output.dmg' >&2
    exit 2
fi
app=$1
output=$2
[[ -d "$app/Contents" && "$app" == *.app && "$output" == *.dmg ]] || { echo 'Expected an App bundle and .dmg output.' >&2; exit 2; }
[[ ! -e "$output" ]] || { echo 'Refusing to overwrite an existing image.' >&2; exit 2; }
background="$(cd "$(dirname "$0")/.." && pwd)/design/dmg/background.tiff"
[[ -f "$background" ]] || { echo "Missing $background" >&2; exit 2; }
/usr/bin/codesign --verify --deep --strict "$app"

work=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/imdreader-dmg.XXXXXX")
mountpoint="$work/mount"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
cleanup() {
    # The temporary copy shares the bundle ID; keep LaunchServices pointed at the installed app.
    "$lsregister" -u "$mountpoint/iMDReader.app" 2>/dev/null || true
    [[ -d "$mountpoint" ]] && /usr/bin/hdiutil detach "$mountpoint" -quiet -force 2>/dev/null || true
    /bin/rm -rf "$work"
}
trap cleanup EXIT

/bin/mkdir -p "$work/stage/.background" "$mountpoint"
/usr/bin/ditto "$app" "$work/stage/iMDReader.app"
/bin/ln -s /Applications "$work/stage/Applications"
/bin/cp "$background" "$work/stage/.background/background.tiff"
/usr/bin/hdiutil create -volname iMDReader -srcfolder "$work/stage" -fs HFS+ -format UDRW -ov "$work/rw.dmg" -quiet
/usr/bin/hdiutil attach "$work/rw.dmg" -mountpoint "$mountpoint" -noautoopen -quiet

# Window 660x400 pt content; icon centres match render-background.swift.
/usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
    set dmgFolder to (POSIX file "$mountpoint" as alias)
    open dmgFolder
    set w to container window of dmgFolder
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    try
        set pathbar visible of w to false
    end try
    set bounds of w to {200, 120, 860, 548}
    set opts to icon view options of w
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to (POSIX file "$mountpoint/.background/background.tiff" as alias)
    set position of item "iMDReader.app" of dmgFolder to {180, 205}
    set position of item "Applications" of dmgFolder to {480, 205}
    update dmgFolder without registering applications
    delay 1
    close w
end tell
APPLESCRIPT

/usr/bin/SetFile -a V "$mountpoint/.background" 2>/dev/null || true
/bin/sync
/usr/bin/hdiutil detach "$mountpoint" -quiet
/usr/bin/hdiutil convert "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$output" -quiet
/usr/bin/hdiutil verify "$output"
/usr/bin/shasum -a 256 "$output"
echo 'DMG created. Public distribution still requires Developer ID signing, notarization and Gatekeeper verification.'
