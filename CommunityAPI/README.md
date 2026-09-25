# BZOGAK Community API

BZOGAK 앱의 외부 도서 서비스를 한 곳에서 호출하는 Vercel Functions 프로젝트다.

같은 배포에서 앱의 공개 페이지도 제공한다.

- 서비스 소개: `https://bzogak.aib.vote/`
- App Store: `https://apps.apple.com/us/app/%EA%B8%80%EC%A1%B0%EA%B0%81-%EC%84%9C%EB%9E%8D/id6808131632?l=ko`
- 개인정보처리방침: `https://bzogak.aib.vote/privacy`
- 문의하기: `https://bzogak.aib.vote/support`

## Local check

```sh
npm install
npm run typecheck
npm test
```

실제 제공자 요청을 확인하려면 `.env.example`을 참고해 로컬 환경변수를 설정한다. 키 파일은 커밋하지 않는다.

## Vercel

- Root Directory: `CommunityAPI`
- Region: Seoul (`icn1`)
- Runtime: Node.js 24.x
- 개인정보 처리방침: 배포 주소의 `/privacy`

필수 환경변수:

```text
KAKAO_REST_API_KEY
ALADIN_TTB_KEY
NAVER_CLIENT_ID
NAVER_CLIENT_SECRET
DATA4LIBRARY_AUTH_KEY
GOOGLE_PLACES_API_KEY
```

도서 캐시 전환 시 추가할 서버 환경변수:

```text
YES24_API_KEY
KNOWAI_RANKING_CACHE_URL
KNOWAI_RAKUTEN_SEARCH_URL
BZOGAK_BOOK_BRIDGE_SECRET
```

일본어·영어 화면의 주변 서점/도서관은 Google Places API (New)를 사용한다. `GOOGLE_PLACES_API_KEY`는 서버에만 두고 Places API (New)를 활성화한다. 앱은 Google Maps URL로 장소를 연다. 한국어 화면은 기존 Kakao 검색을 사용한다. 일본어 도서 검색은 Rakuten 캐시가 있으면 이를 먼저 조회하고, 없거나 대기 중이면 Google Books(키 설정 시), 그다음 Open Library를 사용한다. 영어는 Google Books → Open Library 순서다. 도서 검색어와 위치는 서버의 `POST` 본문으로만 보낸다.

Rakuten 키는 앱에 넣거나 다른 프로젝트의 키를 복사하지 않는다. `KNOWAI_RAKUTEN_SEARCH_URL`과 bridge secret이 설정되면, 일본어 검색은 KnowAI의 비공개 대기열을 통해 고정 IP Oracle VM에서 처리한다. 캐시가 아직 없거나 대기 중이면 Google Books → Open Library를 사용한다. bridge 미설정 시 기존 직접 Rakuten 호출 설정만 사용한다. 기존 `books_rakuten`의 AI 인기 도서 20권은 임의 제목·ISBN 검색 결과로 사용하지 않는다. 일본어 인기 도서 순위는 `language=ja` 요청에서 별도 Rakuten 판매순 일일 스냅샷을 사용하며, 미준비 상태에 한국 순위를 대신 반환하지 않는다.

한국어 판매·대출 순위는 `KNOWAI_RANKING_CACHE_URL`과 bridge secret이 설정되면 KnowAI Supabase의 하루 단위 스냅샷에서 조회한다. 스냅샷이 아직 없을 때만 기존 Aladin/Data4Library를 호출한다. bridge 장애에서는 공급자 호출이 요청마다 늘어나지 않도록 오류를 반환한다. 판매 순위 제공자는 YES24이며, 한국어 도서 검색도 `YES24_API_KEY`가 있으면 YES24 우선·Kakao 대체로 전환한다. 설정 전에는 기존 Aladin 검색을 유지한다. 출처와 원본 상세 링크를 앱에 표시한다. 데이터베이스 SQL과 배포 순서는 KnowAI의 `docs/BZOGAK_BOOK_CACHE.md`를 따른다.

주변 장소, 관련 글과 책 검색은 위치와 검색어가 URL 또는 CDN 캐시에 남지 않도록 `POST` 요청과 `no-store` 응답만 허용한다. 공개 순위는 서버 DB에 캐시한다. 일본어 도서 검색어는 고정 IP VM 작업이 끝날 때까지 비공개 DB 대기열에 보관하고, 성공하면 원문을 삭제한다. 검색 결과는 24시간 제공하고 작업·결과 행은 7일 후 삭제한다.

JSON 요청은 Vercel이 제공하는 `request.body`를 우선 검증한다. 이미 소비한 요청 스트림을 다시 읽지 않으며, 해당 속성이 없는 일반 Node.js 환경에서만 스트림을 읽는다. JSON 객체만 허용하고 8,192바이트 제한을 유지한다. 원본 `Content-Length`가 있으면 먼저 검사하고, 파싱된 객체도 UTF-8 직렬화 크기를 검사한다. 원본 길이가 없는 파싱된 요청은 직렬화 크기만 확인할 수 있다.

관련 회귀 테스트는 `tests/http.test.mjs`에 있으며, 소비된 스트림·파싱된 본문, 잘못된 JSON, 멀티바이트 크기 경계와 메서드 제한을 검사한다. 실제 배포 환경이나 제공자 API를 호출하는 테스트는 아니다. 구현 근거: [Vercel Node.js 요청 본문 안내](https://vercel.com/kb/guide/handling-node-request-body).

## Search discovery

- `robots.txt`: 공개 페이지와 검색용 AI 크롤러의 접근을 허용하고 `/api/`는 제외한다. ChatGPT 검색용 `OAI-SearchBot`은 허용하고 학습용 `GPTBot`은 차단한다.
- `sitemap.xml`: 서비스 소개, 개인정보처리방침과 문의 페이지의 canonical URL을 제공한다.
- `llms.txt`: AI 시스템이 서비스의 기능, 데이터 처리 원칙과 공식 URL을 빠르게 파악하도록 돕는 보조 문서다. Google 검색 순위에는 사용되지 않는다.
- 각 HTML 페이지는 고유한 title, description, canonical, Open Graph, Twitter Card와 JSON-LD를 포함한다.
- 공유 이미지는 홈의 히어로 화면을 그대로 담은 1200 x 630 JPEG이며, 검색 결과용 파비콘은 32 x 32와 96 x 96 PNG를 함께 제공한다.

배포 후 아래 검색 도구에서 `https://bzogak.aib.vote/sitemap.xml`을 제출한다.

1. Google Search Console
2. 네이버 서치어드바이저
3. Bing Webmaster Tools

홈은 Apple 공식 한국어 App Store 배지, iPhone Safari용 Smart App Banner, 헤더·푸터 링크로 공개 앱 페이지를 연결한다. `MobileApplication` 구조화 데이터에도 공개 App Store URL을 추가했다. 실제 앱 평가가 쌓이면 화면에 표시되는 App Store 평점과 `aggregateRating`을 함께 추가해 Google 앱 리치 결과 요건을 충족한다. 출시 전에는 평점이나 리뷰를 임의로 만들지 않는다.
