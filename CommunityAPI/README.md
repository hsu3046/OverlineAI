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

필수 환경변수:

```text
KAKAO_REST_API_KEY
ALADIN_TTB_KEY
NAVER_CLIENT_ID
NAVER_CLIENT_SECRET
DATA4LIBRARY_AUTH_KEY
```
