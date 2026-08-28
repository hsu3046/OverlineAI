# Local Quote TTS

## Scope

Overline reads only the saved quote body with `AVSpeechSynthesizer`. Notes and book metadata are not spoken, and no text is sent to a server for narration.

## Voice Selection

- Settings exposes separate voice choices for Korean, English, and Japanese.
- `iPhone Auto Select` is the safe initial choice. Overline asks iOS to choose a compatible voice for the quote language instead of assuming the highest-quality catalog entry is ready to use.
- The remaining choices are the voices that `AVSpeechSynthesisVoice.speechVoices()` exposes to Overline. This public API doesn't provide the download icon or installation state shown in Settings, so the app doesn't describe these choices as installed voices.
- The selected `AVSpeechSynthesisVoice.identifier` is stored in `UserDefaults` and assigned directly to every utterance.
- Exact voice choices are ordered Premium, Enhanced, then Default quality. Within the same quality, the exact locale is preferred.
- If an iOS update or voice removal makes a saved identifier unavailable, Overline returns to `iPhone Auto Select`.

This exact-identifier path is intentional. Selecting a voice only by language can produce a different voice from the one chosen in Accessibility settings, particularly across iOS versions.

### Siri voice limitation

The Siri voice selected in iOS Settings and the voices exposed to third-party apps through `AVSpeechSynthesisVoice` aren't guaranteed to be the same catalog. The public API has no accessor for the current Siri voice and no Siri-specific voice trait. If a Siri asset isn't returned by `speechVoices()`, Overline can't select it by a supported identifier.

### Device diagnostics

Opening Settings > Read Aloud records the device catalog in the `SpeechVoice` logging category. Each `tts_voice` entry contains the name, language, quality, traits, and exact identifier returned by iOS. An identifier containing `siri` is marked with `siri_identifier=true`; this is a diagnostic hint, not a public Siri API guarantee.

## Audio Session

`AVSpeechSynthesizer.usesApplicationAudioSession` remains `false`. Overline does not create a separate spoken-audio processing session for quote playback.

## Device Test

1. On iPhone, install a high-quality voice from Settings > Accessibility > Read & Speak > Voices.
2. In Overline, open Insights > Settings > Read Aloud. Confirm that `SpeechVoice` logs contain the catalog returned by the device.
3. Start with iPhone Auto Select, then preview the explicit Enhanced or Premium choices returned to Overline.
4. Open a saved quote and confirm that playback uses the chosen voice.
5. Relaunch the app and confirm that the selection is retained.
