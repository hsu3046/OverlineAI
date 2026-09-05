# 1.0.1 배포 준비

기준일: 2026-09-05. 사용자가 최초 출시 완료를 확인했다. 최초 업로드 기록은 1.0 (4)이며, 실제 출시 빌드 번호는 App Store Connect에서 최종 대조한다.

## 대상

- 버전: 1.0.1 / Build 5
- Bundle ID: `vote.aib.bzogak.ios` (기존 앱 유지)
- 최소 iOS: 17.0 (변경 없음)
- 지원 언어: 한국어만 (`developmentRegion = ko`, `CFBundleLocalizations = [ko]`). App Store Connect의 설명 언어와 별개로 빌드 메타데이터를 수정한다.
- 기준 소스: main `93b014f`
- 로컬 AI는 이번 버전에 포함하지 않음: [1.1 구현 및 조사 이슈 #21](https://github.com/hsu3046/OverlineAI/issues/21)

## Build 4 이후 앱 변경

- `7fc1b24`: 백업 헤더/버전을 본문보다 먼저 검증하고, 내보내기와 가져오기 모두 50MiB 한도 적용.
- `0d6385b`: 현재 앱이 접근 가능한 예전 구독 인증 정보 정리. 현재 API 키나 다른 앱의 비공개 Keychain 삭제는 제외.
- `015ad3c`: 보관함 가져오기/초기화/복구 후 이전 AI 결과 저장 방지. 생성 중 새로 입력한 프롬프트 보존.
- 한국어 UI에 맞춰 앱의 기본/지원 언어 선언을 영어에서 한국어로 정정.
- 웹사이트 갤러리 및 서버 요청 파싱 수정은 별도 배포 사항이며 앱 업데이트 설명에 포함하지 않음.
- 백업 내보내기와 설정 UI 개선은 Build 4에 이미 포함된 내용이므로 신규 기능으로 다시 소개하지 않음.

## 새로운 기능 문구

```text
독서 기록을 더 안정적으로 관리할 수 있도록 개선했습니다.

• 백업 파일의 형식과 용량 확인을 강화했습니다.
• 보관함을 가져오거나 초기화한 뒤 이전 AI 응답이 저장될 수 있는 문제를 수정했습니다.
• AI가 답변을 만드는 동안 새로 입력한 내용이 유지되도록 개선했습니다.
• 앱의 지원 언어 표시를 한국어로 바로잡았습니다.
```

## App Review Notes 추가 문구

```text
Version 1.0.1 is a maintenance update. It improves backup format and size validation, prevents stale AI results from being saved after library import/reset/restore, preserves newly entered prompts during generation, and removes accessible legacy subscription credentials without removing current API keys.

The app's main features, supported devices, and external AI services are unchanged. This update does not introduce on-device LLM insight generation. No app account registration or login is required. Existing review access instructions for optional external AI features remain applicable.

The app UI supports Korean only. The bundle's development language and supported localization declaration have been corrected from English to Korean to match the existing UI.
```

기존 심사 Notes의 기능 접근 안내는 유지하고 이 변경 요약을 추가한다. 실제 연결 정보와 비밀값은 공개 문서에 기록하지 않는다.

## 검증 상태

- [x] LibraryBackupCodec 자동 테스트 8개
- [x] LibraryContentRevision 자동 테스트 7개
- [x] LegacyCredentialCleanup 자동 테스트 3개
- [x] Release Archive 생성
- [x] Archive 앱/ONNX 서명 및 최소 OS 검증
- [ ] 실기기 업그레이드 회귀 테스트
- [x] App Store Connect 업로드 성공 (2026-09-05 09:18 KST)
- [ ] Apple 후속 처리 완료 및 빌드 선택 가능 여부 확인
- [ ] 1.0.1에 Build 5 선택 후 사용자 심사 제출

### 로컬 Archive 결과

- 언어 수정 전 Archive: `~/Library/Developer/Xcode/Archives/2026-09-05/BZOGAK 1.0.1 (5).xcarchive`. 보존용이며 업로드하지 않는다.
- 한국어 반영 Archive: `~/Library/Developer/Xcode/Archives/2026-09-05/BZOGAK 1.0.1 (5) Korean.xcarchive`. 재생성 및 서명/최소 OS 검증 완료. 업로드 시 이 파일을 사용한다.
- 한국어 Archive의 실제 plist에서 `CFBundleDevelopmentRegion = ko`, `CFBundleLocalizations = [ko]` 확인 완료. App Store의 표시 반영은 새 버전 승인/출시 후 확인한다.
- Xcode 결과: `ARCHIVE SUCCEEDED`, 로그에 warning/error 없음.
- 실제 Archive 메타데이터: Version `1.0.1`, Build `5`, Bundle ID `vote.aib.bzogak.ios`.
- 앱 deep/strict 서명 검사 및 ONNX 개별 strict 검사 통과.
- 앱 plist, ONNX plist, ONNX Mach-O의 최소 OS 모두 `17.0`.
- Archive는 Apple Development 서명이며, 배포용 export에서 `Apple Distribution: AIB Inc. (9BF5ZBVYYF)`로 재서명했다. IPA의 앱/포함 프레임워크 strict 서명 검사 및 앱/ONNX 최소 OS 17.0, 버전 1.0.1 (5), 한국어 선언을 확인했다.
- 2026-09-05 09:18 KST Xcode `Upload succeeded`, `Uploaded package is processing`, `EXPORT SUCCEEDED` 확인. Apple 후속 처리 및 App Store Connect 빌드 선택 가능 여부는 아직 확인하지 않았다.
- ONNX dSYM 누락 경고는 기존과 동일하다. 업로드는 성공했으나 해당 프레임워크의 크래시 심볼 분석에 제한이 있다.
- 첫 export는 macOS rsync와 PATH의 다른 rsync 간 옵션 충돌로 패키징에 실패했다. 해당 명령에만 `PATH=/usr/bin:/bin:/usr/sbin:/sbin`을 적용해 export 및 upload 성공. 전역 환경/앱 코드는 변경하지 않았다.
- 배포용 IPA: `/tmp/BZOGAK-1.0.1-Build5-Export/BZOGAK.ipa`. 업로드 로그: `/tmp/bzogak-1.0.1-upload.log`.
- 실기기 테스트/심사 제출/출시는 미실시.

## 실기기 확인

1. 출시 앱의 데이터를 백업하고, 앱을 삭제하지 않은 채 동일 Bundle ID의 새 빌드로 업데이트한다. 책/글조각/메모/독서 기록/API 키 유지 확인.
2. 백업 내보내기와 다시 가져오기, 지원하지 않는 버전 및 손상된 파일의 오류 안내를 확인한다. 실제 데이터 대신 테스트 백업으로 확인한다.
3. AI 생성 도중 보관함 교체/초기화/복구 시 오래된 응답이 저장되지 않는지 확인한다. 생성 도중 새로 입력한 문장이 지워지지 않아야 한다.
4. 카메라 밑줄긋기, 기본/고품질 낭독, 잠금 상태의 백그라운드 재생, 기존 외부 AI 연결을 짧게 회귀 확인한다.

## 등록 순서

1. 업로드 완료. TestFlight에서 `1.0.1 (5)`의 Apple 처리가 완료되면 실기기에서 업데이트 및 주요 기능을 확인한다.
2. 기존 앱에서 새 iOS 버전 `1.0.1`을 만들고(이미 있으면 해당 버전 사용), 빌드 추가에서 `5`를 선택한다. 새 앱/Bundle ID를 만들지 않는다.
3. 새로운 기능과 심사 Notes를 입력하고 기존 URL/개인정보/스크린샷이 실제 동작과 일치하는지 확인한다.
4. App Store 버전 출시에서 `수동으로 버전 출시`를 선택하고 저장한다. 자동 출시는 선택하지 않는다.
5. 사용자가 `심사에 추가` 후 제출 목록의 `심사를 위해 제출`까지 진행한다. 심사에 추가만으로는 제출되지 않는다.
6. 승인 후 개발자 출시 대기 상태에서 사용자가 `이 버전 출시`를 눌러 공개한다. 이번 작업은 업로드만 수행했으며 심사 제출/출시는 수행하지 않았다.

Apple 공식 절차: https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version
