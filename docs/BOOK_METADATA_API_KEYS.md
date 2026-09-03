# Book Metadata API

BZOGAK의 도서 검색은 `CommunityAPI`를 통해 Kakao와 Aladin을 호출한다. 외부 제공자 키는 앱에 포함하지 않는다.

## 검색 순서

1. Aladin 도서 검색
2. 결과가 없거나 Aladin 요청이 실패하면 Kakao 도서 검색

Google Books는 사용하지 않는다.

## 앱 설정

배포 빌드는 `Config/Overline.xcconfig`에 등록된 BZOGAK 운영 서버를 사용한다. 로컬 개발 서버나 Preview 배포를 사용할 때만 `Config/Secrets.xcconfig`에서 주소를 덮어쓴다.

```xcconfig
// $() keeps // from being interpreted as an xcconfig comment.
OVERLINE_API_BASE_URL = https:/$()/preview.example.com
```

`Config/Secrets.xcconfig`는 Git에 포함하지 않는다. 앱은 최종 `Info.plist`의 `OverlineAPIBaseURL` 값을 읽는다.

## 서버 설정

Vercel 프로젝트의 Root Directory를 `CommunityAPI`로 지정하고 다음 환경변수를 등록한다.

```text
KAKAO_REST_API_KEY
ALADIN_TTB_KEY
NAVER_CLIENT_ID
NAVER_CLIENT_SECRET
DATA4LIBRARY_AUTH_KEY
```

키는 앱 번들, 로그, 응답에 포함하지 않는다.

## 검증

배포 후 다음 주소가 `{"status":"ok"}`를 반환하는지 확인한다.

```text
https://your-overline-api.vercel.app/api/v1/health
```

그다음 앱을 빌드해 책 추가 화면의 도서 검색을 확인한다. 주소가 비어 있거나 잘못되면 앱은 서버 설정이 필요하다는 안내를 표시한다.
