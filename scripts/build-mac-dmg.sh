#!/bin/bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
    echo 'Usage: build-mac-dmg.sh /path/iMDReader.app /path/new-output.dmg' >&2
    exit 2
fi
app=$1
output=$2
[[ -d "$app/Contents" && "$app" == *.app && "$output" == *.dmg ]] || { echo 'Expected an App bundle and .dmg output.' >&2; exit 2; }
[[ ! -e "$output" ]] || { echo 'Refusing to overwrite an existing image.' >&2; exit 2; }
/usr/bin/codesign --verify --deep --strict "$app"
staging=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/imdreader-dmg.XXXXXX")
trap '/bin/rm -rf "$staging"' EXIT
/usr/bin/ditto "$app" "$staging/iMDReader.app"
/bin/ln -s /Applications "$staging/Applications"
/usr/bin/hdiutil create -volname iMDReader -srcfolder "$staging" -format UDZO -imagekey zlib-level=9 "$output"
/usr/bin/hdiutil verify "$output"
/usr/bin/shasum -a 256 "$output"
echo 'DMG created. Public distribution still requires Developer ID signing, notarization and Gatekeeper verification.'
