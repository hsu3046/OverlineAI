import type { IncomingMessage, ServerResponse } from "node:http";

const privacyPolicyURL = "https://bzogak.aib.vote/privacy";

export default function privacyPolicy(request: IncomingMessage, response: ServerResponse): void {
  if (request.method !== "GET") {
    response.statusCode = 405;
    response.setHeader("Allow", "GET");
    response.end("Method Not Allowed");
    return;
  }

  response.statusCode = 308;
  response.setHeader("Location", privacyPolicyURL);
  response.setHeader("Cache-Control", "public, max-age=3600, s-maxage=86400");
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.end();
}
