# App Design System

## Direction

Native glass for floating navigation and controls; neutral, readable content.
No hand-drawn shine, layered glass borders, or decorative shadows. Preserve
book artwork, highlighter colors, camera overlays, and semantic error colors.

## Shared Implementation

`Overline/OverlineDesignSystem.swift` owns dimensions, role fonts, search fields,
content surfaces, glass controls, and primary/secondary action styles.
`Overline/OverlineTypography.swift` retains the Dynamic Type-aware Pretendard
scale. Do not introduce arbitrary fixed text sizes for ordinary UI labels.

| Role | Default size / treatment |
| --- | --- |
| Page title | 22 pt bold |
| Section / field label | 17 pt semibold |
| Body / text entry / search | 17 pt regular |
| Action / selector | 15 pt semibold |
| Supporting detail | 13 pt regular |
| Minimum touch target | 44 pt |
| Search / single-line field | 48 pt minimum height |
| Horizontal field inset | 16 pt |
| Page inset | 20 pt |
| Content surface | 8 pt radius, adaptive system fill |
| Floating control | Native capsule glass |

Heights are minima where text can grow. SF Symbols, camera geometry, book
covers, highlighter swatches, rating stars, and tutorial targets have their own
functional sizing; do not mechanically resize them as body text.

## Applied Surfaces

- Capture: shared main/secondary action style, neutral canvas, native feedback.
- Books: shared search, selectors, neutral rows and editor fields.
- Insights: shared search, one content surface for the composer, neutral saved
  cards, native control surface for prompt selection.
  The composer and saved cards use the emphasized content variant: adaptive
  tertiary fill at 55% opacity and a 0.5 pt, 6% primary border for subtle separation.
- Community: same search shell and neutral cards; preserve its remote-search
  submission, focus, clear, and book-selection behavior.
- Book / highlight / reading-record editors: shared surfaces, 17 pt input text,
  48 pt minimum ordinary fields, shared toolbar touch targets.
- Book selection: shared search above scrolling rows, with existing filtering.
- Settings: preserve native Form, Picker, Toggle and secure-key semantics.
- Reader: shared neutral canvas and saved-draft surface; playback/camera UI
  keeps its functional geometry.

Search clearing and querying remain unchanged. System sheets, native Form and
system pickers intentionally retain platform behavior rather than counterfeit
glass. System materials handle accessibility settings; physical-device checks
for Reduce Transparency, large Dynamic Type, keyboard and dark mode remain
part of release QA.

## Sources

- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
