# Typography

Overline uses Pretendard Variable as its default text typeface. A single variable font file covers the full weight range while keeping the app bundle smaller than a set of static font files.

## Font asset

- Font: Pretendard Variable 1.3.9
- Source: https://github.com/orioncactus/pretendard/releases/tag/v1.3.9
- Bundle file: `Overline/Resources/Fonts/PretendardVariable.ttf`
- License: SIL Open Font License 1.1
- License copy: `Overline/Resources/Fonts/Pretendard-OFL.txt`
- SHA-256: `3090ccde0442bb347aa7685d9ba8b17436a60682df6e8f92a9a670de14056e22`

The font is registered through `UIAppFonts` in `Config/Info.plist`. Xcode copies synchronized resources to the app bundle root, so the registered filename is `PretendardVariable.ttf`.

## SwiftUI usage

`OverlineTypography.swift` maps the standard SwiftUI text styles to Pretendard and uses `Font.custom(_:size:relativeTo:)`. This preserves Dynamic Type scaling.

```swift
Text("본문")
    .font(.overline(.body))

Text("강조")
    .font(.overline(.headline, weight: .bold))
```

`OverlineApp` also sets `.overline(.body)` at the root so text without an explicit style uses Pretendard by default.

## Intentional exceptions

- SF Symbols and camera HUD icons keep their system sizing and symbol rendering.
- Serif quote styling and rounded memo styling remain system fonts because they communicate a distinct content type.
- System-owned navigation and control surfaces may continue to use the iOS system font.

## Updating the font

1. Download an official Pretendard release.
2. Replace `PretendardVariable.ttf` and `Pretendard-OFL.txt` together.
3. Update the version and SHA-256 above.
4. Build Debug and Release, then confirm the font and license files exist in the app bundle.
