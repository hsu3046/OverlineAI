#!/usr/bin/env python3
"""Check that visible Korean string-catalog entries have matching translations."""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOGS = (
    ROOT / "Overline/Localizable.xcstrings",
    ROOT / "Overline/InfoPlist.xcstrings",
    ROOT / "Overline/AppShortcuts.xcstrings",
    ROOT / "BZOGAKWidgets/Localizable.xcstrings",
    ROOT / "BZOGAKWidgets/InfoPlist.xcstrings",
)
FORMAT_SPECIFIER = re.compile(r"%(?:\d+\$)?(?:lld|lf|ld|d|@)")


def placeholders(value: str) -> list[str]:
    return [re.sub(r"^%\d+\$", "%", match) for match in FORMAT_SPECIFIER.findall(value)]


def main() -> None:
    failures: list[str] = []
    checked = 0
    for catalog_path in CATALOGS:
        catalog = json.loads(catalog_path.read_text())
        if catalog["sourceLanguage"] != "ko":
            failures.append(f"{catalog_path}: source language must be ko")
        for key, entry in catalog["strings"].items():
            # Identifier keys in InfoPlist catalogs are checked through their Korean source value.
            source = entry.get("localizations", {}).get("ko", {}).get("stringUnit", {}).get("value", key)
            if not any("가" <= character <= "힣" for character in source):
                continue
            checked += 1
            for language in ("ja", "en"):
                value = entry.get("localizations", {}).get(language, {}).get("stringUnit", {}).get("value")
                if not value:
                    failures.append(f"{catalog_path.name}: {key!r} missing {language}")
                elif placeholders(source) != placeholders(value):
                    failures.append(f"{catalog_path.name}: {key!r} {language} format mismatch")
    if failures:
        raise SystemExit("\n".join(failures))
    print(f"PASS {checked} Korean catalog entries translated into Japanese and English")


if __name__ == "__main__":
    main()
