# BZOGAK App Store 출시 점검표

기준일: 2026년 9월 4일

## 현재 심사 상태

Version 1.0 / Build 3 제출 후 `Guideline 2.1 - Information Needed - New App Submission` 추가 정보 요청을 받았다. 사용자는 실기기 영상 촬영을 완료했다. 최신 패치 재제출용 영문 답변·첨부 PDF를 준비했으며, 2026년 9월 4일 11:01 KST에 Version 1.0 / Build 4 업로드를 완료했다. 답변 입력, 제출 빌드 선택 및 심사 재제출은 사용자가 진행한다.

### Build 4 업로드 기록

- 소스: `9fd9aca`의 최신 패치에 빌드 번호 `4` 반영. 백업 내보내기, 외부 AI 설정 개선, ONNX 재서명 포함.
- Release Archive 생성 및 App Store 배포용 IPA 내보내기 성공. `Apple Distribution: AIB Inc. (9BF5ZBVYYF)` 서명 확인.
- Archive와 배포용 IPA 모두 앱·ONNX 프레임워크 서명 검사 통과. 앱 plist·프레임워크 plist·프레임워크 실행 파일의 최소 iOS 버전 모두 `17.0`.
- Xcode 업로드 결과: `Upload succeeded`, Apple ID `6808131632`, uploaded build `4`. Apple의 후속 처리 시작을 확인했으며, App Store Connect에서 빌드 선택 가능 여부는 아직 확인하지 않음.
- 경고: 사전 빌드된 `onnxruntime.framework`의 dSYM 누락으로 해당 프레임워크의 디버깅 심볼 업로드 실패. 앱 업로드는 성공했으며, 이 경고는 이후 오류 분석에 영향을 줄 수 있음.
- Archive: `~/Library/Developer/Xcode/Archives/2026-09-04/BZOGAK 1.0 (4).xcarchive`. 이 작업에서는 실기기 설치·실행, 심사 답변 전송, 제출을 수행하지 않음.

- [심사 대응·실기기 촬영·증빙 점검표](APP_REVIEW_PREPARATION.md)
- [영문 답변·Notes 및 첨부 PDF](APP_REVIEW_NOTES.md): 실제 영상·기기 정보와 최종 제출 빌드에 맞춰 사용

### 다음 빌드 준비

- 소스의 다음 빌드 번호는 `5`로 올렸다. Build 5의 Archive, 실기기 검증 및 업로드는 아직 수행하지 않았다.
- Build 4 업로드 이후 백업 형식·크기 검증, 접근 가능한 구독 인증 정보 정리, 보관함 교체 중 AI 결과 저장 방어를 추가했다. 이 수정들은 기존 Build 4 바이너리에 포함되지 않는다.
- 다음 업로드 시 새 빌드를 실기기로 검증하고 심사 Notes·영상·빌드 선택을 실제 제출 버전에 맞춘다. 기존 Build 4 업로드 기록은 그대로 보존한다.

아래 코드 완료 항목에는 업로드 이후 작업 브랜치 변경도 포함되어 있다. 최초 제출은 `742c185`의 Build 3였으며 후속 수정이 포함되지 않았다. 심사 제출 시에는 선택한 빌드의 동작과 촬영한 영상을 대조한다.

## 코드에서 완료한 항목

- Xcode 26 및 iOS 26 SDK 요구사항 충족
- 첫 출시 대상을 iPhone 세로 화면으로 제한
- 카메라, 마이크, 음성 인식, 위치 권한 설명 등록
- 백그라운드 오디오 모드 등록
- 수출 규정의 비면제 암호화 사용 여부를 `false`로 선언
- Privacy Manifest에 UserDefaults, 시스템 부팅 시간, 디스크 공간 사용 이유 등록
- 수집 항목에 정확한 위치, 검색 기록, 기타 사용자 콘텐츠를 앱 기능 목적으로 선언
- 외부 AI 전송은 기본 꺼짐이며, 사용자가 직접 켜야만 동작
- OpenAI와 Anthropic의 비공식 구독 토큰 경로 제거 및 현재 앱이 접근 가능한 예전 구독 토큰 삭제. 다른 Bundle ID·서명 팀의 비공개 Keychain은 접근하거나 삭제하지 않음
- 위치, 관련 글과 책 검색을 `POST` 본문으로 전송하고 서버 응답 캐시 비활성화
- 앱 안 개인정보 처리방침과 오픈소스 라이선스 화면 추가
- 앱의 개인정보 처리방침을 AIB 공식 사이트의 전용 공개 주소로 분리
- ONNX Runtime 프레임워크의 최소 iOS 버전 표기를 앱과 동일하게 보정한 뒤 재서명하고 빌드 중 검증
- Version 1.0, Build 3의 App Store Connect 업로드 및 심사 제출 완료

## 배포 전에 사용자가 할 일

- [x] Community API를 앱보다 먼저 Vercel Production에 배포
- [x] `https://bzogak.aib.vote/privacy`가 로그인 없이 열리는지 확인
- [ ] App Store Connect의 개인정보 처리방침 URL에 `https://bzogak.aib.vote/privacy` 입력
- [x] 실제 문의가 가능한 `https://bzogak.aib.vote/support` 공개
- [ ] App Store Connect의 Support URL에 `https://bzogak.aib.vote/support` 입력
- [ ] 앱 개인정보 답변을 아래 표와 동일하게 입력
- [ ] 새 연령 등급 설문을 완료하고 관련 글의 외부 블로그 콘텐츠 노출을 사실대로 답변
- [ ] 콘텐츠 권리 항목에서 Kakao, NAVER, Aladin, 도서관 정보나루 API 사용과 원문 링크 제공 방식을 설명
- [ ] `APP_REVIEW_NOTES.md`가 안내하는 영문 TXT를 심사 메시지 답변과 Notes 양쪽에 입력하고 촬영한 영상·설명 PDF·필요한 기존 증빙 첨부
- [ ] 6.9형 iPhone 스크린샷 5장을 저작권·개인정보가 없는 예시 데이터로 촬영
- [ ] 앱 이름, 부제, 설명, 키워드와 카테고리를 `APP_STORE_METADATA.md`대로 입력
- [x] Build 4 Archive 및 배포용 IPA에서 아래 ONNX 메타데이터와 코드 서명 검증 완료
- [ ] 실기기에서 아래 회귀 테스트 완료

연령 등급에서는 `사용자 생성 콘텐츠`만 있음으로 답변하고, `무제한 웹 접근`, `소셜 미디어`, `메시지 및 채팅`, `광고`는 없음으로 답변한다. 공개 블로그 검색 결과를 앱 안에서 작성하거나 재배포하는 기능이 아니라 읽기 전용으로 보여주며, 원문은 시스템 브라우저에서 연다.

이는 기능 항목에 대한 구분이며, 폭력·성적 콘텐츠 등 내용별 빈도가 자동으로 `없음`이라는 뜻이 아니다. 실제 외부 검색 결과와 보호 장치를 확인한다. 읽기 전용이라는 이유만으로 UGC 신고·차단 요건의 면제를 단정하지 않는다.

## App Privacy 권장 답변

| 데이터 유형 | 사용자와 연결 | 추적 | 목적 |
| --- | --- | --- | --- |
| 정확한 위치 | 아니요 | 아니요 | 앱 기능 |
| 검색 기록 | 아니요 | 아니요 | 앱 기능 |
| 기타 사용자 콘텐츠 | 아니요 | 아니요 | 앱 기능 |

앱은 계정, 광고 ID, 결제 정보, 연락처를 수집하지 않는다. 분석 SDK와 광고 SDK도 사용하지 않는다. App Store Connect 답변은 배포된 서버의 실제 로그 및 외부 제공자 정책과 다시 대조한다.

## ONNX Archive 검증

App Store에 올릴 Archive 안에서 다음 세 값이 모두 `17.0`인지 확인한다.

- `BZOGAK.app/Info.plist`의 `MinimumOSVersion`
- `BZOGAK.app/Frameworks/onnxruntime.framework/Info.plist`의 `MinimumOSVersion`
- `onnxruntime.framework/onnxruntime` 실행 파일의 iOS `minos`

셋 중 하나라도 다르면 업로드하지 않는다. Xcode에서 `Product > Clean Build Folder`를 실행한 뒤 새 빌드 번호로 다시 Archive한다.

세 값이 일치한 뒤 `codesign --verify --strict`로 `onnxruntime.framework`과 `BZOGAK.app`을 모두 검증한다. 프레임워크의 `Info.plist`를 수정한 뒤 재서명하지 않으면 실기기 설치에서 `0xe8008001` 오류가 발생한다.

## 실기기 회귀 테스트

- [ ] 신규 설치 후 카메라 권한 허용·거부와 설정 이동
- [ ] 밑줄긋기 1페이지 및 이어 밑줄긋기 2페이지
- [ ] 읽어주기 여러 페이지, 임시 보관 3개, 7일 만료
- [ ] 화면 잠금 및 앱 백그라운드에서 iPhone 음성과 고품질 음성 계속 재생
- [ ] Bluetooth 이어폰 연결, 제어 센터 재생·정지, 오디오 경로 복원
- [ ] 401MB 고품질 음성 팩의 다운로드, 취소, 공간 부족, 삭제
- [ ] `AI로 글 보내기`가 꺼진 상태에서 외부 AI 요청이 발생하지 않음
- [ ] 동의를 켠 뒤 각 API 키 연결 테스트와 동의를 다시 끈 뒤 차단 확인
- [ ] 위치 권한 허용·거부 상태의 내 주변 화면
- [ ] 관련 글 검색어 지우기, 외부 링크 열기, 인기 도서 필터
- [ ] 오프라인 상태에서 로컬 보관함·OCR·기본 낭독이 유지되고 외부 기능은 오류 안내 표시
- [ ] 보관함 초기화 확인창과 최근 초기화 복구
- [ ] 설정의 개인정보 처리방침 및 모든 라이선스 파일 열기

## 운영 일정

- NAVER Developers 검색 API 기존 키는 2027년 6월 30일까지 지원된다. 그 전에 NAVER API HUB로 이전한다.
- 개인정보 처리, 외부 제공자, 보관 기간이 바뀌면 앱의 안내문, 공개 `/privacy`, Privacy Manifest, App Store Connect 답변을 함께 갱신한다.

## Apple 공식 참고

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)
- [Export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
