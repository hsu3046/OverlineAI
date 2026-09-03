# App Review Notes

BZOGAK (Korean display name: 글조각 서랍) is a Korean-language personal reading companion for physical books. No account, purchase, or demo credentials are required.

## Core review path

1. Open the Capture tab and allow camera access.
2. In Underline mode, point the camera at a printed book page. Capture the page, swipe across recognized lines, and save the selected passage.
3. In Read Aloud mode, capture up to 10 pages, tap Done, and then tap Play. Playback can continue while the app is in the background or the screen is locked.
4. The Bookshelf stores books, passages, reading records, and generated insights locally on the device.
5. Community provides read-only nearby bookstores/libraries, public book rankings, and book-related NAVER/Daum blog search results. Search result titles and short snippets are shown in the app, and the original article opens in the system browser. Users cannot publish, comment, message, follow, or browse arbitrary web addresses in the app. Location is requested only for Nearby.

## Photos, OCR, and copyrighted text

Camera images are processed for OCR and are not retained after recognition. Read Aloud drafts are local, limited to three items, and automatically deleted after seven days. The app does not upload captured page images, host a public library of book pages, or provide copyrighted books. Users choose passages from books they possess for private reading and may initiate sharing themselves.

## AI features

External AI features are optional and disabled by default. A user must enter their own provider API key and explicitly enable “Send text to AI” in Settings before any passage, memo, or book information is sent. The user can revoke this permission at any time. OpenAI, Anthropic, Google, and OpenRouter are accessed only through their documented API-key endpoints; consumer subscription tokens are not supported.

AI credentials are not required to review camera OCR, local reading, the bookshelf, or the core app. API keys are stored in the iOS Keychain and are never logged.

## On-device high-quality voice

The optional Supertonic 3 voice pack is approximately 401 MB. It is downloaded only after the user taps Download and confirms. The pack runs on-device, can be removed in Settings, and is excluded from backup. The built-in iPhone voice works without this download.

## Permissions and background mode

- Camera: printed-page OCR and ISBN scanning.
- Microphone and Speech Recognition: optional on-device voice memo transcription.
- Location When In Use: nearby bookstores and libraries.
- Background Audio: continuation of user-started text-to-speech playback.

Privacy policy: `https://bzogak.aib.vote/privacy`
