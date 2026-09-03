# BZOGAK App Store 출시 점검표

기준일: 2026년 9월 3일

## 코드에서 완료한 항목

- Xcode 26 및 iOS 26 SDK 요구사항 충족
- 첫 출시 대상을 iPhone 세로 화면으로 제한
- 카메라, 마이크, 음성 인식, 위치 권한 설명 등록
- 백그라운드 오디오 모드 등록
- 수출 규정의 비면제 암호화 사용 여부를 `false`로 선언
- Privacy Manifest에 UserDefaults, 시스템 부팅 시간, 디스크 공간 사용 이유 등록
- 수집 항목에 정확한 위치, 검색 기록, 기타 사용자 콘텐츠를 앱 기능 목적으로 선언
- 외부 AI 전송은 기본 꺼짐이며, 사용자가 직접 켜야만 동작
- OpenAI와 Anthropic의 비공식 구독 토큰 경로 제거 및 예전 토큰 삭제
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
- [ ] 심사 메모에 `APP_REVIEW_NOTES.md` 내용을 붙여 넣기
- [ ] 6.9형 iPhone 스크린샷 5장을 저작권·개인정보가 없는 예시 데이터로 촬영
- [ ] 앱 이름, 부제, 설명, 키워드와 카테고리를 `APP_STORE_METADATA.md`대로 입력
- [ ] 다음 배포 Archive에서 아래 ONNX 메타데이터와 코드 서명 검증 완료
- [ ] 실기기에서 아래 회귀 테스트 완료

연령 등급에서는 `사용자 생성 콘텐츠`만 있음으로 답변하고, `무제한 웹 접근`, `소셜 미디어`, `메시지 및 채팅`, `광고`는 없음으로 답변한다. 공개 블로그 검색 결과를 앱 안에서 작성하거나 재배포하는 기능이 아니라 읽기 전용으로 보여주며, 원문은 시스템 브라우저에서 연다.

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
