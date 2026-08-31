# 로컬 텍스트 낭독

## Scope

Overline은 저장된 인용 본문과 페이지 읽어주기 본문만 낭독한다. 메모와 책 정보는 읽지 않으며, 낭독할 텍스트를 서버로 전송하지 않는다.

한국어는 다음 두 방식을 선택할 수 있다.

- `iPhone 음성`: 기존 `AVSpeechSynthesizer`와 설치된 iOS 음성 팩을 사용한다.
- `고품질 온디바이스`: 선택 설치한 Supertonic 3 모델을 ONNX Runtime으로 기기에서 실행한다.

영어와 일본어는 iPhone 음성을 사용한다.

## 낭독 조절

- 읽기 속도는 `0.8×`부터 `1.6×`까지 `0.05×` 단위로 조절한다.
- 문장 간격은 `0.0초`부터 `0.6초`까지 `0.05초` 단위로 조절한다.
- 설정값은 저장된 글조각과 페이지 읽어주기가 공유하며 재실행 뒤에도 유지한다.
- iPhone 음성은 문장별 `AVSpeechUtterance` 대기열에 속도와 뒤쪽 간격을 적용한다.
- 고품질 온디바이스 음성은 Supertonic의 `speed`와 `silenceDuration`에 같은 설정을 적용한다.
- 슬라이더를 움직이는 동안에는 표시값만 바꾸고, 손을 뗐을 때 재생 설정을 갱신한다.

## 고품질 온디바이스 음성

- 음성 팩은 앱에 포함하지 않고 사용자가 선택했을 때 약 401MB를 내려받는다.
- 모델과 음색 파일은 고정된 리비전과 SHA-256으로 검증한 뒤 `Application Support`에 저장한다.
- 다운로드 파일은 iCloud 및 기기 백업에서 제외하고 완전 파일 보호를 적용한다.
- 다운로드 후에는 인터넷 연결 없이 합성한다. 낭독 본문은 외부로 전송하지 않는다.
- 여성 5종(`F1`~`F5`)과 남성 5종(`M1`~`M5`)을 모두 제공하며 기본은 `F1`이다.
- 생성 단계는 `균형` 8단계를 기본으로 하고, 사용자가 `고음질` 12단계를 선택할 수 있다.
- 모델은 앱 시작이나 카메라 전환 때 준비하지 않는다. 페이지 촬영을 완료하거나 임시 글을 불러온 뒤 첫 문장을 소리 없이 준비하고, 낭독 세션이 끝나면 메모리에서 해제한다.
- 페이지 읽어주기는 문장 단위로 합성한다. 현재 문장을 재생하는 동안 다음 문장을 미리 합성해 문장 사이 대기를 줄인다.
- 고품질 음성 팩이 없거나 한국어가 아닌 경우 기존 iPhone 음성 경로를 유지한다.

의존성은 ONNX Runtime Swift Package `1.24.2`에 고정한다. 모델은 Supertonic 3 리비전 `3cadd1ee6394adea1bd021217a0e650ede09a323`, Swift 추론 도우미는 Supertonic 저장소 커밋 `7e2804f96016a7028cb1ed627353c61c1e9dd281`을 기준으로 한다.

## iPhone 음성 선택

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

## 오디오 세션

저장된 글조각과 페이지 읽어주기는 백그라운드 낭독을 위해 앱의 `playback` 오디오 세션을 사용한다. iPhone 음성도 `AVSpeechSynthesizer.usesApplicationAudioSession`을 `true`로 설정하고, 재생 전 앱 오디오 세션을 활성화한다.

고품질 온디바이스 음성은 재생 직전에 공유 오디오 세션을 `playback` 카테고리와 `default` 모드로 활성화한다. 이 설정은 AirPods를 포함한 Bluetooth A2DP 출력 경로를 유지한다. 연속 페이지 낭독 중에는 세션을 유지하고, 미리 듣기 또는 낭독이 완전히 끝나면 `AVAudioEngine`을 중지한 뒤 세션을 비활성화한다.

페이지 읽어주기와 저장된 글조각은 Background Audio 모드를 사용한다. 사용자가 재생을 시작한 뒤에는 화면 잠금과 다른 앱 사용 중에도 낭독을 유지하며, 잠금 화면·제어 센터·AirPods의 재생과 일시정지 명령을 처리한다. 글조각 이어듣기는 이전·다음 글조각 명령도 지원한다. 출력 장치가 분리되면 예기치 않은 스피커 재생을 막기 위해 일시정지한다. 앱을 강제로 종료한 경우에는 iOS가 프로세스를 끝내므로 재생을 유지하지 않는다.

## 글조각 이어듣기

- 책장의 `최근 글조각`에서 스피커 버튼을 누르면 여러 글조각을 선택해 연속 재생할 수 있다.
- `최근` 범위는 저장 시각 기준 최신 30개를 보여주고, 선택한 항목을 오래된 순서부터 읽는다.
- `책별` 범위는 선택한 책의 최신 30개를 보여주고, 페이지 번호가 있으면 페이지 순서로 읽는다.
- 선택 상한은 30개다. 현재 글조각을 읽는 동안 다음 음성만 준비해 선택 수가 시작 시간과 메모리를 늘리지 않게 한다.
- 잠금 화면에는 인용 본문 대신 책 제목과 현재 순서만 표시한다.
- 페이지 읽어주기와 글조각 낭독은 동시에 재생하지 않는다. 한쪽을 시작하면 다른 쪽은 현재 위치를 보존하고 오디오 제어권을 넘긴다.

## 실제 기기 검증

1. On iPhone, install a high-quality or premium voice from Settings > Accessibility > Read & Speak > Voices. Siri voices are not selectable by third-party apps.
2. In Overline, open Insights > Settings > Read Aloud. Confirm that `SpeechVoice` logs contain the catalog returned by the device.
3. Start with Best Quality Auto Select, then preview the explicit Enhanced or Premium choices returned to Overline.
4. Open a saved quote and confirm that playback uses the chosen voice.
5. Relaunch the app and confirm that the selection is retained.
6. 한국어에서 `고품질 온디바이스`를 선택하고 약 401MB 다운로드 안내와 진행률이 표시되는지 확인한다.
7. 다운로드 후 여성 5종과 남성 5종을 각각 미리 듣고 선택값이 재실행 뒤 유지되는지 확인한다.
8. `균형`과 `고음질`을 바꿔 미리 듣기와 페이지 읽어주기에 적용되는지 확인한다.
9. 고품질 음성을 선택한 상태에서 한국어 페이지를 읽고, 첫 문장 준비 표시 뒤 다음 문장들이 연속 재생되는지 확인한다.
10. 영어와 일본어 페이지가 기존 iPhone 음성으로 재생되는지 확인한다.
11. 음성 팩을 삭제하면 iPhone 음성으로 돌아가고 다시 받을 수 있는지 확인한다.
12. AirPods 연결 상태에서 미리 듣기와 페이지 낭독이 AirPods로 출력되고, 앱 안에서도 출력 장치를 바꿀 수 있는지 확인한다.
13. 읽기 속도와 문장 간격을 바꾼 뒤 iPhone 음성과 고품질 온디바이스 음성에 각각 적용되는지 확인한다.
14. 페이지 촬영 완료와 임시 글 복원 직후 자동 재생되지 않고, 재생 버튼을 눌렀을 때만 소리가 시작되는지 확인한다.
15. iPhone 음성과 고품질 온디바이스 음성 각각에서 화면 잠금·앱 전환 중 재생과 잠금 화면 제어가 정상인지 확인한다.
16. 책장의 최근 글조각에서 최근/책별 범위를 바꾸고 최대 30개를 선택해 순서대로 이어지는지 확인한다.
17. 글조각 이어듣기 중 잠금 화면·제어 센터·AirPods에서 재생, 일시정지, 이전, 다음이 동작하는지 확인한다.
18. 페이지 읽어주기와 글조각 이어듣기를 번갈아 시작했을 때 두 음성이 겹치지 않는지 확인한다.

## 라이선스

- Supertonic Swift 추론 도우미: MIT License
- Supertonic 3 모델: OpenRAIL-M
- 모델 다운로드 시 원본 `LICENSE`도 함께 저장한다.
- 출처와 고정 버전은 `docs/THIRD_PARTY_NOTICES.md`에 기록한다.
