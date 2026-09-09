# Capture Tutorial

## Flow

Kiboon's real-screen guidance informs this tutorial. The former standalone
practice screen has been removed. Instructions sit beside the actual controls;
there are no fake book search results, simulated OCR, or duplicate drawing logic.

1. Highlight the real Library + button.
2. Show instructions inside BookEditorSheet. Search or enter a book manually;
   the existing save action advances the guide. Cancelling returns to step 1.
3. Switch to Capture and confirm the destination book using the real selector.
4. Capture a page or import a photo with the existing controls.
5. On successful image preparation, explain underline/rectangle selection.
   Recognition progress hides this instruction. Retaking returns to step 4.
6. Successful capture saving automatically advances to pointers for narration,
   notes, and insights. The wording never claims a save when only browsing.

Every card also has a step counter, Previous, and Next (Finish on step 6).
Users can browse all steps without registering or capturing anything. Navigation
opens/dismisses the actual book editor and switches tabs without invoking save.
Selection instructions can be viewed even before an image is captured.

Registration and capture are real: user-selected books and text remain in the
library. Existing camera/photo permissions and external AI consent rules apply.
The guide never generates records itself or completes an operation on a timer.

## Presentation

The first ordinary launch opens the Library guide. Finish or skip stores
captureTutorialCompletedV2 in UserDefaults. Settings replays the guide after
dismissal. App Intent requests stop the guide without marking it completed.
The coordinator is owned by ContentView and passed through the environment.

Instructions use flexible-height text and accessibility heading focus. The guide
does not add a full-screen input blocker or an animated gesture recognizer.
Cards use the existing StickyTone.yellow.paper for their border and primary action, with a pale
background, larger descriptive headings, and no misleading hand icon.
All cards use overlays and never take up space in the base layout. Steps 4/5
are aligned above the camera frame with an 8-point gap, not inside the preview.
The wider Next button uses dark text; secondary actions and the regular-weight
step counter share a muted readable color. Disabled Previous is separately faded.
Step-specific yellow rings highlight book search (2), the book selector chevrons
(3), Capture (4), and the entire Capture-to-Community menu as one group (6), without changing layout or hit
targets. Step 5 overlays a translucent hand and left-to-right underline inside
the camera. It ignores touches and accessibility, stops after two passes,
hides during drawing/recognition, and respects Reduce Motion and scene activity.

## Icon

Overline/AppIcon.icon copies the supplied design-assets/brand/icon.icon bundle.
Both Debug and Release use AppIcon. The supplied PNG is a visual reference only.
The previous BZOGAK.icon and website icons are unchanged.

## Verification

- Simulator build and all eight LibraryContentRevision scenarios pass.
- iPhone 17e Simulator: real Library + highlight, editor instructions, cancel
  returning to step 1, manual book registration, navigation to Capture,
  destination confirmation, skip, and Settings replay verified.
- Card layout, no-input navigation through all six steps, Previous from
  Capture back to the book editor, and Finish verified on Simulator.
- Updated 4/5 overlays verified on iPhone 17e Simulator: the camera and capture
  button retain their positions and the guide remains above the preview.
- Capture instructions overlay the preview rather than extending its height,
  so the guide does not push the capture controls below the viewport.
- Physical-device camera capture, rectangle OCR, VoiceOver, and large Dynamic
  Type still require device QA before distribution.

## App Color Policy

Shared interface ink, muted ink, accent, and the asset-catalog AccentColor are
neutral grays. Keep the four highlighter colors for highlights, cream/paper
backgrounds, content artwork, and semantic error/destructive colors. New standard
controls should use the shared tokens rather than introducing teal/green accents.
