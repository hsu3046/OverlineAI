# LLM Subscription OAuth

Overline의 인사이트 기능은 API 키 방식 외에 사용자가 본인의 AI 구독 계정을 연결하는 방식을 지원할 수 있다. 이 문서는 2026-06-27 실기기 테스트에서 확인한 OpenAI/Codex, Claude 구독 토큰 연동 정보를 남긴다.

## 결론

- 앱 개발자의 AI 구독을 사용자에게 제공하는 구조가 아니다.
- 사용자가 자기 iPhone 앱에 자기 OpenAI 또는 Claude 구독 토큰을 연결하는 구조다.
- 2026-06-27 실제 iPhone 테스트에서 아래 2개가 모두 성공했다.
  - OpenAI/Codex 구독 access token으로 Overline 인사이트 생성
  - Claude 구독 access token으로 Overline 인사이트 생성
- 현재 구현은 브라우저 OAuth 자동 로그인 전 단계다.
  - 앱 안 설정 화면에 token을 직접 붙여넣어 테스트한다.
  - token은 iOS Keychain에 이 기기 전용으로 저장된다.
  - 배포용 UX에서는 직접 token 입력을 숨기고 `OpenAI로 연결`, `Claude로 연결`, `연결 해제`만 보여주는 방향이 맞다.

## 현재 앱 구현

관련 파일:

- `Overline/LLMSettings.swift`
- `Overline/LLMInsightClient.swift`
- `Overline/InsightsView.swift`

저장 구조:

- API 키: `KeychainStringStore(service: "aib.Overline.llm")`
- 구독 토큰: `KeychainStringStore(service: "aib.Overline.llm.subscription")`
- 인증 모드: `UserDefaults`의 `overline.llm.authMode.<provider>`

지원 상태:

| Provider | API 키 | 구독 토큰 | 비고 |
| --- | --- | --- | --- |
| OpenAI | 지원 | 지원 | Codex/ChatGPT 구독 경로 |
| Claude | 지원 | 지원 | Claude Code OAuth 경로 |
| OpenRouter | 지원 | 미지원 | OpenRouter는 구독 모델이 아님 |
| Gemini | 지원 | 미지원 | 아직 구독 OAuth 미구현 |

## OpenAI / Codex

### 공식적으로 확인된 정보

OpenAI Codex는 OpenAI 모델 로그인 방식으로 2가지를 제공한다.

- ChatGPT 로그인: 구독 access
- API 키: 사용량 기반 access

Codex CLI / IDE Extension은 둘 다 지원한다. ChatGPT로 로그인하면 Codex CLI가 access token을 받아 로컬에 캐시한다. 공식 문서에 따르면 파일 기반 저장소를 쓸 경우 `~/.codex/auth.json`에 토큰이 저장될 수 있고, 이 파일은 비밀번호처럼 취급해야 한다.

참고:

- https://developers.openai.com/codex/auth
- https://auth.openai.com/.well-known/openid-configuration

OpenAI의 OIDC metadata에서 확인한 주요 endpoint:

```text
authorization_endpoint = https://auth.openai.com/api/accounts/authorize
token_endpoint         = https://auth.openai.com/api/accounts/oauth/token
userinfo_endpoint      = https://auth.openai.com/api/accounts/oauth/userinfo
```

### OpenAI access token 발급 방법

#### 방법 A: ChatGPT Business / Enterprise access token

공식 access token UI가 있는 워크스페이스에서는 이 방법이 가장 깔끔하다.

1. https://chatgpt.com/admin/access-tokens 에 접속한다.
2. `Create`를 누른다.
3. 이름과 만료 기간을 정한다.
4. 생성된 token을 즉시 복사한다.
5. Overline iPhone 앱에서 `인사이트 > 설정 > OpenAI > 인증: 구독 > Access token`에 붙여넣는다.

주의:

- OpenAI 문서 기준으로 Codex access token은 ChatGPT Business / Enterprise workspace에서 지원된다.
- 생성 후 token은 다시 볼 수 없으므로 즉시 복사해야 한다.
- 일반 OpenAI Platform API key와 다른 credential이다.

참고:

- https://developers.openai.com/codex/enterprise/access-tokens

#### 방법 B: Codex CLI 로그인 캐시에서 테스트용으로 추출

개인 ChatGPT 구독 계정에서는 access token 생성 UI가 없을 수 있다. 이 경우 테스트 단계에서는 Codex CLI가 받은 로그인 캐시를 사용할 수 있다.

1. 맥북에서 Codex CLI에 ChatGPT로 로그인한다.

```sh
codex login
```

2. 파일 기반 저장소를 쓰고 있다면 access token을 클립보드로 복사한다.

```sh
jq -r '.tokens.access_token // .access_token // empty' ~/.codex/auth.json | pbcopy
```

3. account id가 필요하면 확인한다.

```sh
jq -r '.tokens.account_id // .account_id // empty' ~/.codex/auth.json
```

4. iPhone 앱에 입력한다.

```text
OpenAI > 인증: 구독
Access token: 2번에서 복사한 값
ChatGPT account id: 3번 값이 있으면 입력
```

주의:

- `~/.codex/auth.json`은 비밀번호처럼 취급한다.
- token을 채팅, 이슈, 로그, 커밋에 붙여넣지 않는다.
- Codex 설정이 OS credential store를 쓰면 `auth.json`에 token이 없을 수 있다.
- 이 방법은 테스트용이다. 배포용 UX는 앱 안 OAuth 로그인으로 전환해야 한다.

### Overline의 현재 OpenAI 호출 경로

구독 토큰 선택 시 Overline은 Codex subscription 경로를 사용한다.

```text
POST https://chatgpt.com/backend-api/codex/responses
Authorization: Bearer <access_token>
Accept: text/event-stream
originator: codex_cli_rs
openai-beta: responses=experimental
session_id: <uuid>
chatgpt-account-id: <optional account id>
```

body:

```json
{
  "model": "<selected model>",
  "instructions": "<Overline system prompt>",
  "input": [
    {
      "role": "user",
      "content": "<book context + selected highlights + user prompt>"
    }
  ],
  "stream": true,
  "store": false
}
```

구독 경로에서는 `max_output_tokens`를 보내지 않는다. 이 경로는 Codex 계열 backend와 맞추기 위한 실험 경로이며, 일반 OpenAI Responses API와 다르다.

## Claude

### 공식적으로 확인된 정보

Claude Code는 아래 인증 경로를 지원한다.

- Claude Pro / Max / Team / Enterprise 사용자의 subscription OAuth login
- `CLAUDE_CODE_OAUTH_TOKEN`
- `ANTHROPIC_API_KEY`
- 기타 helper script 기반 credential

공식 문서상 `claude setup-token`은 1년짜리 OAuth token을 생성하고, 이 token은 `CLAUDE_CODE_OAUTH_TOKEN`으로 사용할 수 있다.

참고:

- https://code.claude.com/docs/en/authentication
- https://claude.ai/oauth/claude-code-client-metadata

Claude Code public client metadata에서 확인한 정보:

```text
client_name = Claude Code
client_uri = https://claude.ai
redirect_uris = http://localhost/callback, http://127.0.0.1/callback
grant_types = authorization_code, refresh_token
response_types = code
token_endpoint_auth_method = none
```

### Claude access token 발급 방법

1. 맥북에서 Claude Code CLI를 설치하고 로그인 가능한 상태로 둔다.
2. 아래 명령을 실행한다.

```sh
claude setup-token
```

3. 브라우저 OAuth 인증을 진행한다.
4. 터미널에 출력된 token을 복사한다.
5. Overline iPhone 앱에서 `인사이트 > 설정 > Anthropic > 인증: 구독 > Access token`에 붙여넣는다.

주의:

- `claude setup-token`은 token을 자동 저장하지 않고 터미널에 출력한다.
- 이 token은 Claude 구독을 인증한다.
- token은 비밀번호처럼 취급한다.
- 현재 Overline은 Claude refresh token 자동 갱신을 아직 구현하지 않았다.

### Overline의 현재 Claude 호출 경로

구독 토큰 선택 시 Overline은 Anthropic Messages API에 OAuth beta header를 붙여 호출한다.

```text
POST https://api.anthropic.com/v1/messages
Authorization: Bearer <access_token>
anthropic-version: 2023-06-01
anthropic-beta: claude-code-20250219,oauth-2025-04-20
Content-Type: application/json
```

subscription 경로에서는 system payload를 block 배열로 보낸다.

```json
[
  {
    "type": "text",
    "text": "You are Claude Code, Anthropic's official CLI for Claude."
  },
  {
    "type": "text",
    "text": "<Overline system prompt>"
  }
]
```

그 외 user message에는 Overline의 책 정보, 선택한 글조각, 사용자 질문이 들어간다.

## 실기기 테스트 절차

1. iPhone에 Overline을 설치한다.
2. `인사이트` 탭을 연다.
3. 오른쪽 위 설정을 연다.
4. provider를 `OpenAI` 또는 `Anthropic`으로 선택한다.
5. 인증을 `구독`으로 바꾼다.
6. 발급받은 access token을 붙여넣는다.
7. `현재 모델 테스트`를 누른다.
8. 성공하면 실제 글조각을 선택하고 인사이트 생성을 실행한다.

2026-06-27 확인 결과:

- Codex token: 성공
- Claude token: 성공

## 보안 원칙

반드시 지킬 것:

- token을 git에 넣지 않는다.
- token을 로그에 출력하지 않는다.
- token을 GitHub issue, PR, 채팅에 붙여넣지 않는다.
- token은 Keychain에만 저장한다.
- 테스트용 token은 만료되거나 필요 없어지면 provider 쪽에서 revoke한다.
- 앱 내부 오류 로그에는 provider, model, 성공/실패 여부만 남기고 token 값은 절대 남기지 않는다.

현재 Overline의 저장 정책:

- token은 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`로 저장된다.
- iCloud Keychain 동기화 대상이 아니다.
- 기기 백업/복구를 전제로 한 장기 보관 credential로 설계하지 않았다.

## 배포용으로 바꿀 때 필요한 일

현재는 수동 token 입력 단계다. 배포 전에는 아래가 필요하다.

1. `OpenAI로 연결`, `Claude로 연결` 버튼 추가
2. `ASWebAuthenticationSession` 기반 브라우저 OAuth login
3. PKCE code verifier / code challenge 생성
4. callback URL scheme 또는 universal link 구성
5. token exchange
6. access token / refresh token / account id Keychain 저장
7. 만료 시 refresh token 자동 갱신
8. 401 / 403 발생 시 `다시 연결 필요` UI 표시
9. `연결 해제` 버튼으로 Keychain credential 삭제
10. 직접 token 입력 UI는 개발자/테스트 모드로 숨김

OpenAI는 OIDC metadata가 공개되어 있어 iOS OAuth 구현 경로가 비교적 명확하다. Claude는 Claude Code client metadata는 공개되어 있지만 iOS 앱용 redirect와 배포 정책은 추가 확인이 필요하다.

## 정책/제품 문구 초안

앱 안에는 아래 취지의 문구가 필요하다.

```text
Overline은 AI 구독을 제공하지 않습니다.
사용자는 본인의 OpenAI 또는 Claude 계정을 직접 연결합니다.
연결 토큰은 이 iPhone의 Keychain에만 저장됩니다.
선택한 글조각과 메모는 사용자가 인사이트 생성을 누를 때만 선택한 AI 제공자로 전송됩니다.
```

## 다시 하지 말 것

- 개발자의 OpenAI/Claude 구독 token을 앱에 내장하지 않는다.
- 사용자 여러 명이 하나의 token을 공유하게 만들지 않는다.
- token을 `Secrets.xcconfig`, `Info.plist`, Swift 상수에 넣지 않는다.
- 구독 token을 일반 OpenAI Platform API key처럼 취급하지 않는다.
- OpenRouter를 `구독` 인증 옵션에 넣지 않는다.

