# Local Quote TTS

## Scope

Overline reads only the saved quote body with `AVSpeechSynthesizer`. Notes and book metadata are not spoken, and no text is sent to a server for narration.

## Voice Selection

- Settings exposes separate voice choices for Korean, English, and Japanese.
- Only voices currently installed on the iPhone are listed.
- The selected `AVSpeechSynthesisVoice.identifier` is stored in `UserDefaults` and assigned directly to every utterance.
- The initial selection prefers Premium, then Enhanced, then Default quality. Within the same quality, the exact locale is preferred.
- If an iOS update or voice removal makes a saved identifier unavailable, Overline selects the best currently installed compatible voice and stores the replacement.

This exact-identifier path is intentional. Selecting a voice only by language can produce a different voice from the one chosen in Accessibility settings, particularly across iOS versions.

## Audio Session

`AVSpeechSynthesizer.usesApplicationAudioSession` remains `false`. Overline does not create a separate spoken-audio processing session for quote playback.

## Device Test

1. On iPhone, install a high-quality voice from Settings > Accessibility > Read & Speak > Voices.
2. In Overline, open Insights > Settings > Read Aloud.
3. Select the installed voice for the desired language and use Preview.
4. Open a saved quote and confirm that playback uses the same voice.
5. Relaunch the app and confirm that the selection is retained.
