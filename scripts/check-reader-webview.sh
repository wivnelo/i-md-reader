#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
resources=${1:-"$repo/ReaderApp/Resources"}
output=${2:-$(mktemp -d /tmp/imdreader-webview-results.XXXXXX)}
mkdir -p "$output"
qa=$(mktemp -d /tmp/imdreader-webview-check.XXXXXX)
trap 'rm -rf "$qa"' EXIT
python3 - "$repo" "$qa" <<'PY'
from pathlib import Path
import sys
repo, qa = map(Path, sys.argv[1:])
source = (repo / 'ReaderApp/ReaderWebView.swift').read_text()
start = source.index('    private var datesScript: String {')
end = source.index('    private var appearanceScript:', start)
fixture = 'import Foundation\nstruct DateScriptFixture {\nstruct Document { let dates: DocumentDates }\nlet document: Document\nlet language: String\n'
fixture += source[start:end].replace('private var datesScript', 'var datesScript') + '\n}\n'
(qa / 'DateScript.swift').write_text(fixture)
PY
swiftc -swift-version 6 -parse-as-library "$repo/ReaderCore/Sources/ReaderCore/LocalDocuments.swift" \
  "$qa/DateScript.swift" "$repo/Tests/ReaderWebViewChecks/main.swift" -o "$qa/WebViewChecks"
"$qa/WebViewChecks" "$resources" "$output"
