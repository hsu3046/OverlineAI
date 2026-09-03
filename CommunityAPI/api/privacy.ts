import type { IncomingMessage, ServerResponse } from "node:http";

export default function privacyPolicy(request: IncomingMessage, response: ServerResponse): void {
  if (request.method !== "GET") {
    response.statusCode = 405;
    response.setHeader("Allow", "GET");
    response.end("Method Not Allowed");
    return;
  }

  response.statusCode = 200;
  response.setHeader("Content-Type", "text/html; charset=utf-8");
  response.setHeader("Cache-Control", "public, max-age=3600, s-maxage=86400");
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("Referrer-Policy", "no-referrer");
  response.setHeader(
    "Content-Security-Policy",
    "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  );
  response.end(privacyPolicyHTML);
}

const privacyPolicyHTML = `<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Overline 개인정보 처리방침</title>
  <style>
    :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif; }
    body { margin: 0; color: #20211f; background: #f7f8f7; line-height: 1.65; }
    main { width: min(760px, calc(100% - 40px)); margin: 0 auto; padding: 56px 0 80px; }
    h1 { margin: 0 0 8px; font-size: 2rem; letter-spacing: 0; }
    h2 { margin: 36px 0 10px; font-size: 1.2rem; letter-spacing: 0; }
    p, li { font-size: 1rem; }
    .date { color: #686b66; }
    a { color: #24777b; }
  </style>
</head>
<body>
<main>
  <h1>Overline 개인정보 처리방침</h1>
  <p class="date">시행일: 2026년 9월 3일</p>
  <p>Overline은 종이책의 문장을 밑줄로 남기고 읽어주는 개인 독서 앱입니다. 필요한 정보만 사용하고, 사용자가 이해하고 선택할 수 있는 방식으로 처리합니다.</p>

  <h2>1. 이 iPhone에 보관되는 정보</h2>
  <p>책 정보, 글조각, 메모, 독서 기록, 인사이트와 앱 설정은 사용자의 iPhone에 저장됩니다. 읽어주기에서 임시 보관한 글은 최대 3개까지 7일 동안 저장된 뒤 자동으로 삭제됩니다. 캡처 사진은 OCR 처리가 끝나면 저장하지 않습니다.</p>

  <h2>2. 권한을 사용하는 이유</h2>
  <ul>
    <li>카메라: 책 페이지와 ISBN 바코드를 인식합니다.</li>
    <li>마이크와 음성 인식: 사용자가 말한 메모를 기기에서 글로 바꿉니다.</li>
    <li>위치: 사용자가 내 주변 기능을 열었을 때 가까운 서점과 도서관을 찾습니다.</li>
  </ul>

  <h2>3. 외부로 전송되는 정보</h2>
  <p>주변 장소를 찾을 때 현재 위치가 Overline 서버와 Kakao에 전송됩니다. 관련 글과 도서를 검색할 때 검색어, 책 제목 또는 저자 정보가 Overline 서버와 Kakao, NAVER, Aladin, 도서관 정보나루 중 필요한 제공자에게 전송될 수 있습니다.</p>
  <p>AI 기능은 기본으로 꺼져 있습니다. 사용자가 설정에서 ‘AI로 글 보내기’를 직접 켠 경우에만 글조각, 메모와 책 정보가 선택한 OpenAI, Anthropic, Google 또는 OpenRouter로 전송됩니다. 언제든 설정에서 다시 끌 수 있습니다.</p>

  <h2>4. 저장과 보관 기간</h2>
  <p>Overline 서버는 주변 장소와 관련 글 요청 본문을 앱 데이터로 저장하지 않고, 응답도 캐시하지 않습니다. 다만 호스팅 업체와 외부 제공자는 보안 및 서비스 운영을 위해 접속 기록을 각자의 정책에 따라 처리할 수 있습니다. 외부 제공자에서 처리되는 기간과 방식은 해당 서비스의 개인정보 처리방침을 따릅니다.</p>

  <h2>5. 보안</h2>
  <p>외부 통신은 HTTPS를 사용합니다. 사용자가 입력한 AI API 키는 iOS Keychain에 이 기기 전용으로 저장됩니다. Overline은 광고 식별자를 사용하거나 다른 앱과 활동을 연결해 추적하지 않습니다.</p>

  <h2>6. 사용자의 선택과 삭제</h2>
  <p>AI 전송은 설정에서 언제든 끌 수 있습니다. 저장된 책과 기록은 앱에서 개별 삭제하거나 설정의 보관함 초기화로 지울 수 있습니다. 앱을 삭제하면 iPhone에 저장된 앱 데이터도 함께 삭제됩니다.</p>

  <h2>7. 문의</h2>
  <p>개인정보 관련 문의는 <a href="https://knowai.space">KnowAI 웹사이트</a>를 통해 전달해 주세요.</p>

  <h2>8. 변경 안내</h2>
  <p>이 방침이 바뀌면 시행 전에 이 페이지의 날짜와 내용을 업데이트합니다.</p>
</main>
</body>
</html>`;
