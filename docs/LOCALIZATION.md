# 한국어·일본어·영어 로케일

## TL;DR

앱과 위젯은 한국어를 기본 언어로 사용한다. 앱의 **인사이트 → 설정 → 언어**에서 기기 설정·한국어·일본어·영어를 선택하면 앱 화면과 새 검색 요청에 바로 적용된다. iOS의 앱별 언어 설정에서도 변경할 수 있다. 화면·권한 안내·단축어 문구를 문자열 카탈로그로 관리한다. OCR은 세 언어를 계속 인식하면서 선택한 앱 언어를 우선한다. 도서 검색과 주변 장소는 앱 언어에 따라 서버 제공자를 바꾼다.

| 앱 언어 | 도서 정보 | 주변 서점·도서관 | 장소 열기 |
|---|---|---|---|
| 한국어 | YES24 → Kakao | Kakao | Kakao 장소 URL |
| 일본어 | Rakuten Books 캐시 → Google Books(키 설정 시) → Open Library | Google Places (New) | Google Maps URL |
| 영어 | Google Books(키 설정 시) → Open Library | Google Places (New) | Google Maps URL |

Google Places 서버 키가 없거나 목록을 불러오지 못하면 일본어·영어 주변 화면에서 Google Maps 검색을 직접 열 수 있다. 일본어 인기 도서는 Rakuten Books Book Search API의 `sort=sales`를 일일 캐시해 표시한다. 이는 라쿠텐의 공식 주간 순위가 아니므로 화면에 판매순임을 명시한다. 일본어 대출 순위는 제공하지 않는다. 관련 글과 영어 인기 도서는 한국 출처 기반임을 안내한다.

## 설정

- 앱 지원 언어: `ko`, `ja`, `en`. 번역은 `Overline/Localizable.xcstrings`, `Overline/InfoPlist.xcstrings`, `Overline/AppShortcuts.xcstrings`에 있다.
- 앱 내 언어 선택은 `overline.appLanguage`에 저장한다. 이전 버전이 앱 도메인의 `AppleLanguages`에 저장한 선택값은 첫 실행에 이 키로 옮긴다. `기기 설정에 따름`은 번들의 시스템 현지화 결과를 따른다. 화면의 `LocalizedStringKey`는 SwiftUI 환경의 locale을, 동적 문자열은 `LocalizedStringResource`의 locale을 사용한다. 일반 `String(localized:…, locale:)`의 locale은 번역 조회 언어를 바꾸지 않으므로 사용하지 않는다.
- 위젯 번역: `BZOGAKWidgets/Localizable.xcstrings`, `BZOGAKWidgets/InfoPlist.xcstrings`.
- `CommunityAPI` 서버에 `GOOGLE_PLACES_API_KEY`를 설정하고 Places API (New)를 활성화해야 앱 안의 일본어·영어 주변 목록을 사용할 수 있다. 키를 앱에 포함하지 않는다.
- `GOOGLE_BOOKS_API_KEY`는 선택 사항이다. 키가 없거나 Google Books가 실패하면 Open Library로 검색한다.
- 일본어 도서 검색은 기존 Rakuten 키·고정 IP를 쓰는 KnowAI Oracle VM의 검색 작업으로 처리한다. CommunityAPI는 KnowAI 비공개 bridge에 검색을 대기시키고 캐시 결과를 읽는다. 최초 요청은 처리 완료 전까지 Google Books(키 설정 시) 또는 Open Library를 표시한다. `knowai-space`의 AI 인기 도서 동기화 테이블은 일반 도서 검색에 사용하지 않는다.
- 일본어 인기 도서 순위는 동일 VM에서 7개 Rakuten Books 장르의 판매순을 하루 한 번 읽고 한국 순위와 분리된 `bzogak_rakuten_ranking_snapshots`에 최대 100권씩 저장한다. `books_rakuten`의 AI 관련 자체 점수 순위와 혼동하지 않는다. 새 DB 테이블·VM cron·두 서버 배포가 완료되기 전에는 일본어 화면이 한국 순위로 돌아가지 않고 준비 중 오류를 표시한다.
- 앱에서 보내는 `language`는 선택한 앱 언어이고, 주변 검색의 `region`은 기기 지역이다. OCR과 낭독은 캡처된 본문의 언어를 별도로 판별한다.

## 검증

1. 앱의 인사이트 → 설정 → 언어에서 한국어·일본어·영어를 각각 선택한다. 재시작 없이 책장 첫 화면, 탭, 도서 등록, 촬영, 인사이트, 커뮤니티, 설정의 번역과 새 검색 요청 언어가 바뀌는지 확인한다. `기기 설정에 따름`과 iOS 앱별 언어 설정도 확인한다. 위젯과 권한 안내는 시스템 언어에 따라 별도로 확인한다.
2. 한국어 가로 본문과 일본어 가로·세로 본문, 영어 가로 본문을 촬영한다. 한 줄 긋기, 사각형 선택, 전체 저장을 각각 확인한다. 일본어 세로쓰기의 실기기 조건과 한계는 [일본어 OCR 검증](JA_LOCALIZATION_VALIDATION.md)에 기록돼 있다.
3. 한국어·일본어·영어 제목과 ISBN으로 도서 검색을 확인한다. 제목/저자뿐 아니라 정확한 판본·ISBN·표지·출판사 누락 여부를 검토한다.
4. 위치 권한을 허용하고 한국어는 Kakao, 일본어·영어는 Google Places 결과와 Google Maps 열기를 확인한다. Google 키가 없는 경우 Maps 직접 검색 동작을 확인한다.
5. 음성 메모가 선택한 앱 언어로 전사되는지, AI 인사이트/태그가 선택 언어로 생성되고 OCR 교정이 원문 언어를 유지하는지 확인한다.

자동 검증: `python3 Tests/Localization/check.py`, `npm test` (`CommunityAPI`), `bash Tests/OCRDocumentRecognition/run.sh`, iOS Simulator Debug 빌드. 2026-09-25 기준 일본어·영어 시뮬레이터 책장 첫 화면 표시와 Open Library의 일본어·영어 실응답을 확인했다. iPhone 16 Pro Max에서 앱의 이전 일본어 선택값 이관과 촬영·탭의 일본어 표시는 확인했다. 운영 API에서는 YES24 도서 검색 10권, YES24 베스트셀러 1페이지, Data4Library 대출 순위 5페이지, 일본어 Google Places 20곳을 확인했다. 일본어 제목 `ノルウェイの森`은 최초 대체 결과 후 VM의 1분 cron을 거쳐 Rakuten Books 20권으로 전환됐다. ISBN `9784062748681`도 같은 경로에서 라쿠텐 1권으로 전환되고 ISBN이 일치했다. 일부 묶음 상품은 표준 ISBN이 아닌 Rakuten 상품 코드를 `isbn` 필드에 제공하므로 판본 선택 시 확인이 필요하다. 촬영·권한·지도 전환은 실기기에서 별도로 확인해야 한다.

일본어 인기 도서 순위 운영 검증(2026-09-25): VM에서 7개 장르 각 100권을 새 테이블에 저장하고 매일 20:20 UTC 갱신 cron을 추가했다. 운영 브라우저에서 일본어 전체 1페이지 `source=rakuten`, 소설 5페이지 81위부터, 한국어 전체 1페이지 `source=yes24`를 확인했다. iPhone 16 Pro Max에 새 앱을 설치·실행했고 일본어 촬영·탭 표시는 스크린샷으로 확인했다. 실기기의 커뮤니티 순위 화면을 직접 탭해 보는 수동 확인은 남아 있다.

## 제공자 근거

- [Google Books API](https://developers.google.com/books/docs/v1/using): `q`, `langRestrict`, 도서 검색 필드.
- [Rakuten Books Book Search API](https://webservice.rakuten.co.jp/documentation/books-book-search): 제목·ISBN 검색, App ID/Access Key, 품절 도서 포함, 서지 필드.
- [Open Library Search API](https://openlibrary.org/dev/docs/api/search): `lang`은 선호 언어이며 언어 필터가 아니므로 제목·ISBN 일치를 우선한다.
- [Google Places Nearby Search (New)](https://developers.google.com/maps/documentation/places/web-service/nearby-search): 장소 유형, 언어·지역, 필드 마스크.
- [Google Maps URLs](https://developers.google.com/maps/documentation/urls/get-started): 장소 열기와 키 없는 검색 링크.
