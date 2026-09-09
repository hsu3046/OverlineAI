# Capture Navigation

- Selected bottom tabs use a subtle monochrome background (8% ink), without
  a selected outline or custom shadow.
- The first tab displays the remembered CaptureExperienceMode title and icon.
- Single tap navigates to that mode; long press (0.45 seconds) or double tap
  opens an anchored compact popover above the tab.
- VoiceOver offers a named capture-mode selection action.
- Long press uses SwiftUI's native selection sensory feedback. The popover
  anchors slightly above the top center (15% of tab height) with a bottom arrow so it sits above
  navigation, and uses one regular-material background.
- App-authored UI shadows are removed; system presentation chrome is OS-managed.
- The top segmented mode controls are no longer displayed.
- The existing capture.lastExperienceMode preference persists mode selection.
- Reader-to-highlight changes retain the existing draft/exit confirmation.
  Cancelling keeps the reader mode and label. Selecting Reader again retains
  the existing new-reading confirmation behavior.
- Popover selection is applied after its dismissal to avoid overlapping modal
  transitions. Capture tutorial overlays are clamped to the visible viewport
  after removing the upper mode controls.
- Camera stage aspect ratio is 0.76 (previously 0.84), approximately 45 points
  taller at 360-point width. Imported photo fitting shares this ratio; OCR
  projection still uses the actual view size and 9:16 source frame.

## Book Selection and Highlighters

- The shared book picker searches registered titles and authors, ignoring outer
  whitespace, with an empty-result state and the existing add-book action.
- The search drawer is always visible; sheet height reserves space for it.
- Purple is appended to StickyTone as the stable raw value `purple`. Existing
  color raw values are unchanged. Capture and highlight editing share the
  five-color picker.

## Verification Status

Simulator build, long-press popover, selection outline, and transition to Reader
verified. Physical-device double-tap timing and draft confirmation with actual
reading content still need device QA.
