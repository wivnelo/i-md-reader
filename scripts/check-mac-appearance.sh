#!/bin/bash
set -euo pipefail
# Supply a built Mac .app so tests use its actual localized resources.
repo=$(cd "$(dirname "$0")/.." && pwd)
app=${1:?Usage: check-mac-appearance.sh /path/to/iMDReader.app}
test -f "$app/Contents/Resources/en.lproj/Localizable.strings"
qa=$(mktemp -d /tmp/imdreader-view-regression.XXXXXX)
trap 'rm -rf "$qa"' EXIT
python3 - "$repo" "$app" "$qa" <<'PY'
from pathlib import Path
import plistlib, shutil, sys
repo, app, qa = map(Path, sys.argv[1:])
source = (repo / 'ReaderApp/ReaderScreen.swift').read_text()
start = source.index('private struct MacAppearanceSegments:')
end = source.index('\n#endif', start)
(qa / 'Segments.swift').write_text('import AppKit\nimport SwiftUI\n' + source[start:end].replace('private struct MacAppearanceSegments', 'struct MacAppearanceSegments'))
start = source.index('/// System appearance must not be inferred')
(qa / 'Theme.swift').write_text('import AppKit\nimport SwiftUI\n' + source[start:source.rindex('\n#endif')].replace('private final class MacSystemAppearance', 'final class MacSystemAppearance').replace('private struct MacWindowAppearance', 'struct MacWindowAppearance'))
start = source.index('private struct ReadingAreaTitle:')
end = source.index('\n#endif', start)
(qa / 'Title.swift').write_text('import AppKit\nimport SwiftUI\n' + source[start:end].replace('private struct ReadingAreaTitle', 'struct ReadingAreaTitle'))
contents = qa / 'AppearanceQA.app/Contents'
(contents / 'MacOS').mkdir(parents=True)
(contents / 'Resources').mkdir()
(contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'local.imdreader.AppearanceQA', 'CFBundleExecutable': 'AppearanceQA', 'CFBundlePackageType': 'APPL', 'LSUIElement': True}))
shutil.copytree(app / 'Contents/Resources/en.lproj', contents / 'Resources/en.lproj')
PY
swiftc -swift-version 6 "$repo/ReaderApp/ReaderLanguage.swift" "$repo/ReaderApp/ReaderPalette.swift" \
  "$qa/Segments.swift" "$qa/Theme.swift" "$qa/Title.swift" "$repo/Tests/AppearanceViewChecks/main.swift" \
  -o "$qa/AppearanceQA.app/Contents/MacOS/AppearanceQA"
"$qa/AppearanceQA.app/Contents/MacOS/AppearanceQA"
