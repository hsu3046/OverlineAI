# BZOGAK Community API

BZOGAK 앱의 외부 도서 서비스를 한 곳에서 호출하는 Vercel Functions 프로젝트다.

같은 배포에서 앱의 공개 페이지도 제공한다.

- 서비스 소개: `https://bzogak.aib.vote/`
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
```

주변 장소, 관련 글과 책 검색은 위치와 검색어가 URL 또는 CDN 캐시에 남지 않도록 `POST` 요청과 `no-store` 응답만 허용한다. 인기 도서처럼 개인 정보가 없는 공개 목록만 캐시한다.

JSON 요청은 Vercel이 제공하는 `request.body`를 우선 검증한다. 이미 소비한 요청 스트림을 다시 읽지 않으며, 해당 속성이 없는 일반 Node.js 환경에서만 스트림을 읽는다. JSON 객체만 허용하고 8,192바이트 제한을 유지한다. 원본 `Content-Length`가 있으면 먼저 검사하고, 파싱된 객체도 UTF-8 직렬화 크기를 검사한다. 원본 길이가 없는 파싱된 요청은 직렬화 크기만 확인할 수 있다.

관련 회귀 테스트는 `tests/http.test.mjs`에 있으며, 소비된 스트림·파싱된 본문, 잘못된 JSON, 멀티바이트 크기 경계와 메서드 제한을 검사한다. 실제 배포 환경이나 제공자 API를 호출하는 테스트는 아니다. 구현 근거: [Vercel Node.js 요청 본문 안내](https://vercel.com/kb/guide/handling-node-request-body).

## Search discovery

- `robots.txt`: 공개 페이지와 검색용 AI 크롤러의 접근을 허용하고 `/api/`는 제외한다. ChatGPT 검색용 `OAI-SearchBot`은 허용하고 학습용 `GPTBot`은 차단한다.
- `sitemap.xml`: 서비스 소개, 개인정보처리방침과 문의 페이지의 canonical URL을 제공한다.
- `llms.txt`: AI 시스템이 서비스의 기능, 데이터 처리 원칙과 공식 URL을 빠르게 파악하도록 돕는 보조 문서다. Google 검색 순위에는 사용되지 않는다.
- 각 HTML 페이지는 고유한 title, description, canonical, Open Graph, Twitter Card와 JSON-LD를 포함한다.

배포 후 아래 검색 도구에서 `https://bzogak.aib.vote/sitemap.xml`을 제출한다.

1. Google Search Console
2. 네이버 서치어드바이저
3. Bing Webmaster Tools

App Store 출시 후 홈의 `SoftwareApplication` 구조화 데이터에 공개된 App Store URL을 추가한다. 실제 앱 평가가 쌓이면 화면에 표시되는 App Store 평점과 `aggregateRating`을 함께 추가해 Google 앱 리치 결과 요건을 충족한다. 출시 전에는 평점이나 리뷰를 임의로 만들지 않는다.
