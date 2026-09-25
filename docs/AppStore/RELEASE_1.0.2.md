# 1.0.2 배포 준비

기준일: 2026-09-09. 로컬 검증 및 Release Archive 완료. 사용자 승인 후 Xcode 자동 서명 갱신으로 배포 프로파일 문제를 해결하고 IPA export와 배포 서명 검증을 완료했다. 17:03 KST에 1.0.2 (6) 업로드 성공 및 Apple 후속 처리 시작을 확인했다. 심사 제출·출시는 하지 않았다.

## 버전과 범위

- 앱과 위젯 모두 Version 1.0.2 / Build 6.
- 기존 앱 식별자 `vote.aib.bzogak.ios` 유지. 위젯 `vote.aib.bzogak.ios.widgets` 추가.
- 최소 iOS 17.0, 한국어 지원 유지.
- 마지막 로컬 배포 기록은 1.0.1 (5). App Store Connect의 최신 업로드 번호는 이번 작업에서 확인하지 못했으므로 업로드 전 중복 여부를 확인한다.
- `5784081`의 캡처·튜토리얼·디자인·독서 기록 개선과 이후 위젯 작업 포함. 로컬 LLM 인사이트는 포함하지 않는다.

## 새로운 기능

```text
저장한 문장을 홈 화면에서도 만나보세요.

• 글조각 위젯과 인기 도서 위젯을 추가했습니다.
• 사진 보관함에서 책 페이지를 불러와 글조각으로 저장할 수 있습니다.
• 밑줄이나 네모로 선택한 문장을 자동으로 인식해 저장하도록 개선했습니다.
• 책 등록과 글조각 저장을 안내하는 튜토리얼을 추가했습니다.
• 독서 기록에 책갈피 페이지를 남길 수 있습니다.
• 책 선택 검색과 보라색 형광펜을 추가하고, 앱 아이콘과 화면 디자인을 다듬었습니다.
• 자동 교정·AI 태그 처리와 인기 도서 로딩의 안정성을 개선했습니다.
```

## App Review Notes 추가 문구

```text
Version 1.0.2 adds Home Screen widgets, photo-library import for OCR, a guided tutorial, book-selection search, and optional bookmark pages in reading records. It also refines capture controls and the visual design. No account creation, login, or in-app purchase is required.

To try capture: register a book from the Books tab, return to the first tab, then capture a page or use the photo icon to import an image. Draw an underline or rectangle to recognize and save the selected text automatically, or use the save-all control. The first tab's long-press menu switches between highlighting and narration. The tutorial can be advanced without completing each action.

To try widgets: first save a text clipping in the app, then add the app's widgets from the iPhone Home Screen widget gallery. The quote widget supports small, medium, and large sizes and an optional book filter. Quotes are scheduled in five-minute slots; actual refresh timing is controlled by iOS. Tapping a quote opens its book page, not an editing sheet. The large widget also shows currently reading books. The rankings widget supports medium and large sizes and offers bestseller or library-loan rankings.

The app shares a derived local reading snapshot with its widget through an App Group. The primary library remains in its existing location. API keys and private notes are not included in this snapshot. Optional external AI still requires the user's API key and content-transfer consent. On-device LLM insight generation is not part of this release.
```

기존 심사 접근 안내·외부 서비스 설명을 유지하고 위 변경 요약을 추가한다. 예전 영상이나 테스트 결과를 새 빌드에서 촬영·검증한 것으로 표기하지 않는다.

## 자체 검증 결과

- [x] 자동 테스트 34개: 백업 8, 보관함 변경·OCR 메타데이터·책갈피 9, 인기 도서 캐시 6, 예전 인증 정보 정리 3, 위젯 8.
- [x] 위젯 5분 간격 / 약 6시간 타임라인, 최근 50개 필터, 순환, 딥 링크 파싱, 저장 파일 복구 검사.
- [x] 시뮬레이터 Debug 설치·실행 성공. 튜토리얼 1~5단계 진행과 사진 불러오기·5가지 색상 버튼 노출 확인. 이후 시뮬레이터 종료로 UI 검증 중단.
- [x] 최종 소스 Release Archive 성공, 빌드 warning/error 없음.
- [x] Archive 앱 deep/strict 서명 검사 통과. 앱과 위젯 App Group entitlement 일치.
- [x] Archive 앱/위젯 버전 1.0.2 (6), 최소 iOS 17.0 확인. 앱 한국어 선언 확인.
- [x] ONNX plist와 Mach-O 최소 iOS 모두 17.0 확인.
- [x] 자체 검토 수정: 표지 다운로드·디코딩 동시 작업 최대 3개, 스냅샷 요청은 현재 글조각만 준비.
- [x] 자체 검토 수정: 자동 OCR 교정·AI 태그 응답 및 재시도에 보관함 contentRevision 검사 추가. 가져오기·초기화·복구 이전 작업은 적용하지 않음.
- [x] 배포용 IPA export: 사용자 승인 후 `-allowProvisioningUpdates`로 프로파일 갱신, `EXPORT SUCCEEDED` 확인.
- [x] IPA 앱 deep/strict 및 ONNX strict 서명 검증. 앱·위젯의 App Group 일치, `get-task-allow=false`, 버전 1.0.2 (6), 최소 iOS 17.0 확인.
- [ ] 최종 수정 후 시뮬레이터 재실행 및 실기기 회귀 테스트.
- [x] Apple 서버 패키지 분석 및 업로드 성공: `Upload succeeded`, `Uploaded package is processing`, `EXPORT SUCCEEDED` 확인.
- [ ] Apple 후속 처리 완료 및 TestFlight 빌드 선택 가능 여부 확인.

업로드 경고: 사전 빌드된 `onnxruntime.framework`의 dSYM이 없어 심볼 업로드가 실패했다. 앱 업로드 자체는 성공했으며 해당 프레임워크의 크래시 분석에 제한이 있다. 기존 버전과 동일한 경고다.

자동 테스트는 순수 Swift 회귀 테스트이며 전체 UI나 실제 외부 AI 호출의 종단 검증을 대신하지 않는다. 새 CaptureView의 비동기 revision 방어는 코드 검토·Release 컴파일 완료, 실제 요청 중 보관함 교체 시나리오는 아래 실기기 항목으로 남긴다.

## 배포 프로파일 해결 기록

`xcodebuild -exportArchive` 결과:

1. `vote.aib.bzogak.ios.widgets`용 App Store 배포 프로파일 없음.
2. 기존 앱 배포 프로파일에 App Groups capability와 `group.vote.aib.bzogak` 권한 없음.

사용자 승인 후 Xcode `-allowProvisioningUpdates`로 재실행해 두 문제 모두 해결했다. 앱 코드나 기존 Bundle ID는 변경하지 않았다. Xcode에 등록된 다른 계정의 인증 경고는 있었지만 AIB 팀의 export는 정상 완료됐다. 웹에서 별도 버튼을 누를 필요는 없었다.

`Config/AppStoreExportOptions.plist`는 `destination=export`이며 업로드하지 않는다. 업로드에는 별도의 임시 옵션 파일을 사용했다. 앱과 위젯에 `group.vote.aib.bzogak` entitlement와 배포용 `get-task-allow=false`가 포함됐음을 확인했다.

## 로컬 결과물

- Archive: `/tmp/BZOGAK-1.0.2-Build6.xcarchive`
- 보존 Archive: `~/Library/Developer/Xcode/Archives/2026-09-09/BZOGAK 1.0.2 (6).xcarchive` (Xcode Organizer에서 확인 가능).
- Archive 로그: `/tmp/BZOGAK-1.0.2-archive.log`
- 실패한 export 로그: `/tmp/BZOGAK-1.0.2-export.log`
- 성공한 export 로그: `/tmp/BZOGAK-1.0.2-export-auto.log`
- 배포 서명 IPA: `/tmp/BZOGAK-1.0.2-Build6-Export/BZOGAK.ipa`
- 업로드 로그: `/tmp/BZOGAK-1.0.2-upload.log`
- Archive는 개발 서명이며 export한 IPA는 배포 서명이다. `/tmp` 결과물은 임시 보관이다.

## 제출 전 실기기 확인

1. 출시 앱에서 백업한 뒤 앱 삭제 없이 업데이트. 책·글조각·독서 기록·API 키 보존 확인.
2. 카메라와 사진 가져오기, 가로 사진과 iCloud 사진, 밑줄·네모 자동 저장, 모든 글 저장, 지우개, 이어 저장 확인.
3. 튜토리얼 6단계·이전·다음·건너뛰기와 작은 화면에서 겹침 여부 확인.
4. 책 선택 검색, 책갈피 저장·편집, 캡처/낭독 전환과 재실행 후 모드 유지 확인.
5. AI 교정·태그 응답 대기 중 편집 및 보관함 가져오기·초기화·복구 시 오래된 결과가 적용되지 않는지 확인. 실제 보관함 대신 테스트 데이터 사용.
6. 위젯 3가지 크기, 책 필터, 탭 이동, 앱 종료·오프라인·화면 잠금 이후 표시 확인. 5분 정확성을 보장하지 않되 여러 슬롯에서 문장 교체 확인.
7. 일반·다크·틴트 위젯 모드, 큰 글씨와 긴 인용문 확인. 인기 도서 위젯의 오류/캐시 표시 확인.
8. 기본/고품질 낭독과 잠금·백그라운드 재생 회귀 확인.

## 등록 순서

프로파일 갱신, IPA export·서명 검증, 업로드는 완료했다. 남은 작업은 사용자가 진행한다.

1. App Store Connect → 글조각 서랍 → TestFlight에서 1.0.2 (6)의 처리 완료 확인.
2. TestFlight로 실제 iPhone에 업데이트하고 위 실기기 체크리스트 확인. 기존 앱을 삭제하지 않는다.
3. App Store에서 새 iOS 버전 1.0.2를 만들거나 기존 1.0.2를 열고 Build 6 선택.
4. 위 새로운 기능과 심사 Notes를 입력. 실제 UI에 맞는 스크린샷 및 기존 심사 자료 확인.
5. 출시 옵션은 수동 출시로 선택. 사용자가 심사에 추가하고 심사를 위해 제출.
6. 승인 후 사용자가 출시 버튼을 누른다.

[Apple: 새 버전 생성](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version)
