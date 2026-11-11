#!/usr/bin/env python3
"""Validate iMDReader localization resources (no Xcode needed).

Usage: python3 scripts/check-localizations.py [repo-root]
Exit code 1 on any error. Warnings (heuristics for native-speaker review) do not fail.
"""
import json, re, sys
from collections import Counter
from pathlib import Path

LANGS = ["zh-Hans", "zh-Hant", "en", "ja", "ko"]
root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
errors, warnings = [], []
err = errors.append
warn = warnings.append

# 1. Strict UTF-8 for every text resource touched by localization.
for rel in ["ReaderApp/Resources/Localizable.xcstrings", "ReaderApp/Resources/reader.js",
            "ReaderApp/ReaderLanguage.swift", "ReaderWidget/ReaderWidget.swift",
            "ReaderApp/ReaderShortcuts.swift", "ReaderCore/Sources/ReaderCore/LocalDocuments.swift",
            "iMDReader.xcodeproj/project.pbxproj"]:
    path = root / rel
    try:
        data = path.read_bytes()
        text = data.decode("utf-8")  # strict
    except (OSError, UnicodeDecodeError) as exc:
        err(f"{rel}: not strict UTF-8 / unreadable: {exc}")
        continue
    if "\ufffd" in text:
        err(f"{rel}: contains U+FFFD replacement character (mojibake)")

# 2. String Catalog structure.
catalog_path = root / "ReaderApp/Resources/Localizable.xcstrings"
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
if catalog.get("sourceLanguage") != "zh-Hans":
    err(f"sourceLanguage is {catalog.get('sourceLanguage')!r}, expected 'zh-Hans'")
spec = re.compile(r"%(?:(\d+)\$)?(?:[-+ 0#]*)(?:\d+)?(?:\.\d+)?(?:ll|l|h|hh|z|q)?([@dDiuUxXoOfeEgGcCsSp])")

def placeholders(value):
    items = []
    seq = 0
    for match in spec.finditer(value.replace("%%", "")):
        pos = int(match.group(1)) if match.group(1) else (seq := seq + 1)
        kind = match.group(2).lower().replace("d", "i").replace("u", "i")
        items.append((pos, kind))
    return sorted(items)

simplified_probe = None
try:
    from opencc import OpenCC
    simplified_probe = OpenCC("s2t")
except Exception:
    pass

strings = catalog.get("strings", {})
for key, entry in strings.items():
    locs = entry.get("localizations", {})
    values = {}
    for lang in LANGS:
        unit = locs.get(lang, {}).get("stringUnit")
        if not unit:
            err(f"{key!r}: missing {lang}")
            continue
        value = unit.get("value")
        if not isinstance(value, str) or not value.strip():
            err(f"{key!r}: empty {lang}")
            continue
        if unit.get("state") != "translated":
            err(f"{key!r}: {lang} state is {unit.get('state')!r}")
        if value != value.strip() and value.strip() != key.strip():
            warn(f"{key!r}: {lang} has leading/trailing whitespace")
        values[lang] = value
    extra = set(locs) - set(LANGS)
    if extra:
        err(f"{key!r}: unexpected languages {sorted(extra)}")
    if "zh-Hans" in values and values["zh-Hans"] != key:
        err(f"{key!r}: zh-Hans value differs from key ({values['zh-Hans']!r})")
    expected = placeholders(key)
    for lang, value in values.items():
        if placeholders(value) != expected:
            err(f"{key!r}: {lang} placeholders {placeholders(value)} != source {expected}")
        if "\n" in key and value.count("\n") != key.count("\n"):
            err(f"{key!r}: {lang} newline count differs")
    # Heuristics (warnings): script sanity for native review.
    ja, ko, hant = values.get("ja", ""), values.get("ko", ""), values.get("zh-Hant", "")
    if ja and re.search(r"[\u4e00-\u9fff]", key) and not re.search(r"[\u3040-\u30ff]", ja) and len(ja) > 6:
        warn(f"{key!r}: ja has no kana: {ja!r}")
    if ko and len(ko) > 3 and not re.search(r"[\uac00-\ud7a3]", ko):
        warn(f"{key!r}: ko has no hangul: {ko!r}")
    if hant and simplified_probe and simplified_probe.convert(hant) != hant:
        warn(f"{key!r}: zh-Hant may contain simplified characters: {hant!r} -> {simplified_probe.convert(hant)!r}")
    if ja and re.search(r"[\uac00-\ud7a3]", ja) or ko and re.search(r"[\u3040-\u30ff]", ko):
        err(f"{key!r}: ja/ko script mix-up")

# 3. Xcode project regions.
pbx = (root / "iMDReader.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
match = re.search(r"knownRegions = \(([^)]*)\)", pbx)
regions = {item.strip().strip('"') for item in match.group(1).split(",") if item.strip()} if match else set()
for lang in LANGS:
    if lang not in regions:
        err(f"project.pbxproj knownRegions missing {lang}")
if "developmentRegion = zh-Hans" not in pbx:
    err("developmentRegion changed from zh-Hans")

# 4. reader.js has every UI language.
js = (root / "ReaderApp/Resources/reader.js").read_text(encoding="utf-8")
for lang in LANGS:
    if f"'{lang}'" not in js and f'"{lang}"' not in js and not re.search(rf"\b{re.escape(lang)}\b\s*:", js):
        err(f"reader.js has no strings for {lang}")

# 5. Language enum covers every language.
lang_swift = (root / "ReaderApp/ReaderLanguage.swift").read_text(encoding="utf-8")
for lang in LANGS:
    if f'"{lang}"' not in lang_swift:
        err(f"ReaderLanguage.swift does not mention {lang}")

print(f"keys: {len(strings)}; languages: {', '.join(LANGS)}")
print(Counter(len(e.get('localizations', {})) for e in strings.values()))
for item in warnings:
    print("WARN ", item)
for item in errors:
    print("ERROR", item)
print(f"{len(errors)} error(s), {len(warnings)} warning(s)")
sys.exit(1 if errors else 0)
