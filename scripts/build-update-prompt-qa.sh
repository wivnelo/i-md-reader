#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
app=${1:?Built app required}
output=${2:?New QA app path required}
language=${3:-en}
[[ ! -e "$output" ]] || { echo 'Refusing to overwrite QA output.' >&2; exit 2; }
work=$(mktemp -d /tmp/imdreader-update-prompt.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$repo" "$app" "$output" "$work" "$language" <<'PY'
from pathlib import Path
import plistlib,shutil,sys
repo,app,output,work=map(Path,sys.argv[1:5]); language=sys.argv[5]
s=(repo/'ReaderApp/ReaderApp.swift').read_text(); a=s.index('    private var reader: some View {'); b=s.index('    var body: some Scene',a)
view=s[a:b].replace('ReaderScreen()', 'Text("Controlled fixture: no download or installation")')
fixture=(repo/'Tests/UpdatePromptChecks/fixture.swift').read_text().replace('    // PRODUCTION_READER',view)
(work/'main.swift').write_text(fixture)
c=output/'Contents';(c/'MacOS').mkdir(parents=True);(c/'Resources').mkdir()
shutil.copytree(app/'Contents/Resources/en.lproj',c/'Resources/en.lproj')
(c/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.imdreader.UpdatePromptQA.'+language,'CFBundleExecutable':'UpdatePromptQA','CFBundlePackageType':'APPL','QALanguage':language,'QAOutput':str(output)+'.clicked-url.txt'}))
PY
swiftc -parse-as-library -swift-version 6 "$repo/ReaderCore/Sources/ReaderCore/ReleaseUpdate.swift" "$repo/ReaderApp/ReaderLanguage.swift" "$work/main.swift" -o "$output/Contents/MacOS/UpdatePromptQA"
echo "$output"
