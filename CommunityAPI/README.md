# Overline Community API

Overline 앱의 외부 도서 서비스를 한 곳에서 호출하는 Vercel Functions 프로젝트다.

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
- Runtime: Node.js 22 이상
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
