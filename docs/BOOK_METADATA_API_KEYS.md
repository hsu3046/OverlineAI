# Book Metadata API Keys

Overline의 도서 검색은 앱에 포함된 API 키만 사용한다. 사용자가 책 추가 화면에서 Kakao, Aladin, Google 키를 직접 입력하는 흐름은 없다.

## 현재 정책

- 1차 검색: Kakao 도서 검색 API
- fallback: Aladin Open API
- Google Books fallback: 사용하지 않음
- 앱 UI에서 도서 API 키 입력: 제공하지 않음
- 로컬 비밀값 위치: `Config/Secrets.xcconfig`
- 앱 번들에 들어가는 공개 경로: `Config/Info.plist`

`Config/Secrets.xcconfig`는 git에 올리지 않는다. `Config/Secrets.example.xcconfig`만 형식을 남긴다.

## 파일 구조

```text
Config/
  Info.plist                 # 앱 번들 Info.plist. API 키는 build setting 치환값으로만 적는다.
  Overline.xcconfig          # 공통 설정. Secrets.xcconfig를 include한다.
  Secrets.example.xcconfig   # 예시 파일. 실제 키 없음.
  Secrets.xcconfig           # 로컬 실제 키. git ignore.
```

`Config/Overline.xcconfig`:

```xcconfig
KAKAO_REST_API_KEY =
ALADIN_TTB_KEY =
#include? "Secrets.xcconfig"
```

`Config/Info.plist`:

```xml
<key>KakaoRESTAPIKey</key>
<string>$(KAKAO_REST_API_KEY)</string>
<key>AladinTTBKey</key>
<string>$(ALADIN_TTB_KEY)</string>
```

Xcode target 설정:

```text
GENERATE_INFOPLIST_FILE = NO
INFOPLIST_FILE = Config/Info.plist
```

## 이번 장애의 실제 원인

증상:

- 앱에서 책 검색 시 `앱에 도서 검색 API 키가 포함되지 않았습니다.`가 표시됐다.
- 로컬 `Config/Secrets.xcconfig`에는 Kakao, Aladin 키가 있었다.
- API 자체도 curl/ping으로는 정상 응답했다.

헷갈린 지점:

- `xcodebuild -showBuildSettings`에서는 `KAKAO_REST_API_KEY`, `ALADIN_TTB_KEY` 값이 정상으로 보였다.
- 하지만 앱 런타임은 build setting을 직접 읽지 않는다.
- 앱은 최종 `.app/Info.plist`에 들어간 값을 `Bundle.main.object(forInfoDictionaryKey:)`로 읽는다.

결론:

- build setting 값이 보이는 것과 최종 앱 번들에 값이 포함되는 것은 다르다.
- 이 문제는 API 서버, 네트워크, 키 오타가 아니라 최종 앱 산출물에 키가 들어가지 않은 빌드 설정 문제였다.
- 그래서 `GENERATE_INFOPLIST_FILE = YES`와 `INFOPLIST_KEY_*`에 의존하지 않고, 명시적인 `Config/Info.plist`를 `INFOPLIST_FILE`로 지정했다.

## 다시 하지 말 것

아래 방식은 재도입하지 않는다.

- 책 추가 화면에 `Kakao REST API 키` 입력 필드 추가
- Keychain에 도서 검색 API 키 저장
- Google Books fallback 복구
- Run Script로 `OverlineSecrets.plist` 같은 별도 비밀 plist를 생성
- `xcodebuild -showBuildSettings`만 보고 키 포함 여부를 판단

특히 Run Script로 별도 plist를 만드는 방식은 임기응변이다. Apple의 표준 Info.plist 처리 흐름 밖에 파일을 하나 더 만들기 때문에, 코드 서명/아카이브/TestFlight 검증 시 또 다른 확인 포인트가 생긴다.

## 수정할 때 지켜야 할 원칙

1. 키 값은 `Config/Secrets.xcconfig`에만 둔다.
2. 앱이 읽는 키 이름은 `Config/Info.plist`와 `BookMetadataAPIKeyStore`가 일치해야 한다.
3. `Config/Info.plist`는 Copy Bundle Resources에 넣지 않는다. `INFOPLIST_FILE`로만 지정한다.
4. `Config/Secrets.xcconfig`는 git에 포함하지 않는다.
5. 검증은 항상 최종 `.app/Info.plist` 기준으로 한다.

## 검증 절차

### 1. 로컬 키 파일 확인

키 값을 출력하지 말고 길이만 본다.

```sh
python3 - <<'PY'
from pathlib import Path

text = Path("Config/Secrets.xcconfig").read_text()
for name in ["KAKAO_REST_API_KEY", "ALADIN_TTB_KEY"]:
    value = ""
    for line in text.splitlines():
        if line.strip().startswith(name):
            value = line.split("=", 1)[1].strip()
    print(f"{name}: length={len(value)}")
PY
```

기대값:

- `KAKAO_REST_API_KEY`: 빈 값이 아니어야 한다.
- `ALADIN_TTB_KEY`: 빈 값이 아니어야 한다.

### 2. 빌드 설정 확인

```sh
xcodebuild \
  -project Overline.xcodeproj \
  -scheme Overline \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -showBuildSettings 2>/dev/null \
  | awk '/GENERATE_INFOPLIST_FILE|INFOPLIST_FILE|KAKAO_REST_API_KEY|ALADIN_TTB_KEY/ {print}'
```

기대값:

```text
GENERATE_INFOPLIST_FILE = NO
INFOPLIST_FILE = Config/Info.plist
KAKAO_REST_API_KEY = ...
ALADIN_TTB_KEY = ...
```

이 단계는 중간 확인일 뿐이다. 최종 판정은 다음 단계에서 한다.

### 3. 시뮬레이터 앱 번들 확인

```sh
xcodebuild \
  -project Overline.xcodeproj \
  -scheme Overline \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build

python3 - <<'PY'
from pathlib import Path
import plistlib

paths = sorted(
    Path.home().glob(
        "Library/Developer/Xcode/DerivedData/Overline-*/Build/Products/Debug-iphonesimulator/Overline.app/Info.plist"
    ),
    key=lambda p: p.stat().st_mtime,
    reverse=True,
)
p = paths[0]
data = plistlib.loads(p.read_bytes())
print(p)
for key in ["KakaoRESTAPIKey", "AladinTTBKey"]:
    value = str(data.get(key, "") or "")
    print(f"{key}: present={key in data}, length={len(value)}, placeholder={value.startswith('$(')}")
PY
```

기대값:

```text
KakaoRESTAPIKey: present=True, length>0, placeholder=False
AladinTTBKey: present=True, length>0, placeholder=False
```

### 4. 실제 iPhone용 앱 번들 확인

실기기 문제가 의심되면 iPhone용 산출물도 따로 본다.

```sh
xcodebuild \
  -project Overline.xcodeproj \
  -scheme Overline \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO

python3 - <<'PY'
from pathlib import Path
import plistlib

paths = sorted(
    Path.home().glob(
        "Library/Developer/Xcode/DerivedData/Overline-*/Build/Products/Debug-iphoneos/Overline.app/Info.plist"
    ),
    key=lambda p: p.stat().st_mtime,
    reverse=True,
)
p = paths[0]
data = plistlib.loads(p.read_bytes())
print(p)
for key in ["KakaoRESTAPIKey", "AladinTTBKey"]:
    value = str(data.get(key, "") or "")
    print(f"{key}: present={key in data}, length={len(value)}, placeholder={value.startswith('$(')}")
PY
```

이 단계가 통과하면 실제 iPhone에 올라가는 앱에도 키가 포함된다.

### 5. API ping

키 자체와 API 문서 파라미터가 정상인지 확인한다. 키 값은 출력하지 않는다.

```sh
python3 - <<'PY'
from pathlib import Path
from urllib import parse, request
import json

values = {}
for line in Path("Config/Secrets.xcconfig").read_text().splitlines():
    if "=" in line:
        name, value = line.split("=", 1)
        values[name.strip()] = value.strip()

def ping_kakao():
    key = values.get("KAKAO_REST_API_KEY", "")
    qs = parse.urlencode({"query": "미움받을 용기", "target": "title", "size": "1"})
    req = request.Request(
        f"https://dapi.kakao.com/v3/search/book?{qs}",
        headers={"Authorization": f"KakaoAK {key}", "Accept": "application/json"},
    )
    with request.urlopen(req, timeout=12) as res:
        payload = json.loads(res.read().decode("utf-8"))
        docs = payload.get("documents") or []
        print(f"Kakao: http={res.status}, documents={len(docs)}, first_title_present={bool(docs and docs[0].get('title'))}")

def ping_aladin():
    key = values.get("ALADIN_TTB_KEY", "")
    qs = parse.urlencode({
        "TTBKey": key,
        "Query": "미움받을 용기",
        "QueryType": "Title",
        "MaxResults": "1",
        "Start": "1",
        "SearchTarget": "Book",
        "Sort": "Accuracy",
        "Cover": "Big",
        "Output": "JS",
        "Version": "20131101",
    })
    with request.urlopen(f"https://www.aladin.co.kr/ttb/api/ItemSearch.aspx?{qs}", timeout=12) as res:
        payload = json.loads(res.read().decode("utf-8-sig"))
        items = payload.get("item") or []
        print(f"Aladin: http={res.status}, items={len(items)}, first_title_present={bool(items and items[0].get('title'))}")

ping_kakao()
ping_aladin()
PY
```

기대값:

```text
Kakao: http=200, documents>=1, first_title_present=True
Aladin: http=200, items>=1, first_title_present=True
```

## 앱 런타임 체크포인트

`BookMetadataAPIKeyStore`는 아래 키 이름을 읽는다.

```swift
Bundle.main.object(forInfoDictionaryKey: "KakaoRESTAPIKey")
Bundle.main.object(forInfoDictionaryKey: "AladinTTBKey")
```

따라서 `Config/Info.plist`의 key 이름과 Swift 코드의 key 이름이 한 글자라도 다르면 앱은 키가 없다고 판단한다.

## 오류별 해석

| 메시지 | 의미 | 먼저 볼 것 |
| --- | --- | --- |
| `앱에 도서 검색 API 키가 포함되지 않았습니다.` | 최종 앱 번들에서 Kakao/Aladin 키를 둘 다 못 읽음 | `.app/Info.plist`의 `present`, `length`, `placeholder` |
| `Kakao 도서 API 요청이 잠시 제한되었습니다.` | Kakao HTTP 429 | 잠시 후 재시도, fallback 확인 |
| `Kakao와 Aladin 검색이 모두 실패했습니다.` | Kakao 실패 후 Aladin도 실패 | 네트워크, 각 API ping, 응답 메시지 |
| 검색 결과 없음 | API 호출은 성공했지만 결과가 없음 | ISBN/제목 검색어, Kakao 결과 없음 시 Aladin fallback 여부 |

## iPhone에서 같은 오류가 계속 뜰 때

1. 최신 빌드 산출물의 `Debug-iphoneos/Overline.app/Info.plist`를 먼저 확인한다.
2. `present=True`, `length>0`, `placeholder=False`가 아니면 빌드 설정 문제다.
3. 산출물이 정상인데 iPhone 앱에서만 오류가 뜨면 기존 설치 앱이 남아 있을 수 있다.
4. iPhone에서 Overline을 삭제하고 Xcode에서 다시 Run 한다.
5. 그래도 같으면 Xcode의 실제 Run 대상 scheme/configuration이 `Debug`인지 확인한다.

## 참고 문서

- Apple: Managing your app's information property list
  - https://developer.apple.com/documentation/bundleresources/managing-your-app-s-information-property-list
- Apple: Build settings reference
  - https://developer.apple.com/documentation/xcode/build-settings-reference
- Kakao Developers: Daum Search 책 검색
  - https://developers.kakao.com/docs/ko/daum-search/dev-guide#search-book
- Aladin Open API manual
  - `/Users/yuhitomi/Downloads/알라딘 Open API 매뉴얼.md`
