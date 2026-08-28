# Local Quote TTS

## Scope

Overline reads only the saved quote body with `AVSpeechSynthesizer`. Notes and book metadata are not spoken, and no text is sent to a server for narration.

## Voice Selection

- Settings exposes separate voice choices for Korean, English, and Japanese.
- `Best Quality Auto Select` is the initial choice. Overline ranks the voices exposed for the quote language and selects Premium, then Enhanced, then Default quality.
- When Premium or Enhanced voices are available, the picker hides Default-quality voices to keep the list focused. If no high-quality pack is available, Default voices remain visible as a fallback.
- The remaining choices are the voices that `AVSpeechSynthesisVoice.speechVoices()` exposes to Overline. Downloading a high-quality voice pack in iPhone Settings makes that supported app voice available for selection.
- The selected `AVSpeechSynthesisVoice.identifier` is stored in `UserDefaults` and assigned directly to every utterance.
- Exact voice choices are ordered Premium, Enhanced, then Default quality. Within the same quality, the exact locale is preferred.
- If an iOS update or voice removal makes a saved identifier unavailable, Overline returns to `Best Quality Auto Select`.

This exact-identifier path is intentional. Selecting a voice only by language can produce a different voice from the one chosen in Accessibility settings, particularly across iOS versions.

### Siri voice limitation

The Siri voice selected in iOS Settings and the voices exposed to third-party apps through `AVSpeechSynthesisVoice` aren't guaranteed to be the same catalog. The public API has no accessor for the current Siri voice and no Siri-specific voice trait. If a Siri asset isn't returned by `speechVoices()`, Overline can't select it by a supported identifier.

Device testing confirmed that the installed Siri voice was not exposed to Overline. Installing a separate high-quality voice pack from the iOS spoken-content settings made the corresponding Premium or Enhanced voice available and resolved the low-quality, choppy playback.

### Device diagnostics

Opening Settings > Read Aloud records the device catalog in the `SpeechVoice` logging category. Each `tts_voice` entry contains the name, language, quality, traits, and exact identifier returned by iOS.

`AVAudioBuffer` zero-byte warnings may still appear in the device console. They were also observed while speech played successfully, so they are not treated as the cause of compact-voice quality.

## Audio Session

`AVSpeechSynthesizer.usesApplicationAudioSession` remains `false`. Overline does not create a separate spoken-audio processing session for quote playback.

## Device Test

1. On iPhone, install a high-quality or premium voice from Settings > Accessibility > Read & Speak > Voices. Siri voices are not selectable by third-party apps.
2. In Overline, open Insights > Settings > Read Aloud. Confirm that `SpeechVoice` logs contain the catalog returned by the device.
3. Start with Best Quality Auto Select, then preview the explicit Enhanced or Premium choices returned to Overline.
4. Open a saved quote and confirm that playback uses the chosen voice.
5. Relaunch the app and confirm that the selection is retained.
