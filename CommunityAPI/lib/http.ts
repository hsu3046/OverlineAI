import type { IncomingMessage, ServerResponse } from "node:http";

export class HTTPError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "HTTPError";
  }
}

export interface HandlerResult {
  body: unknown;
  cacheControl?: string;
}

export type GETHandler = (url: URL) => Promise<HandlerResult>;
export type JSONBody = Readonly<Record<string, unknown>>;
export type POSTHandler = (body: JSONBody) => Promise<HandlerResult>;

export function createGETHandler(handler: GETHandler) {
  return async function handle(request: IncomingMessage, response: ServerResponse): Promise<void> {
    setSecurityHeaders(response);

    if (request.method !== "GET") {
      response.setHeader("Allow", "GET");
      sendJSON(response, 405, { error: "지원하지 않는 요청입니다." }, "no-store");
      return;
    }

    try {
      const host = request.headers.host ?? "localhost";
      const url = new URL(request.url ?? "/", `https://${host}`);
      const result = await handler(url);
      sendJSON(response, 200, result.body, result.cacheControl ?? "no-store");
    } catch (error) {
      if (error instanceof HTTPError) {
        sendJSON(response, error.status, { error: error.message }, "no-store");
        return;
      }

      console.error("community_api_request_failed", safeErrorMessage(error));
      sendJSON(response, 502, { error: "외부 정보를 불러오지 못했습니다." }, "no-store");
    }
  };
}

export function createPOSTHandler(handler: POSTHandler, maximumBodyBytes = 8_192) {
  return async function handle(request: IncomingMessage, response: ServerResponse): Promise<void> {
    setSecurityHeaders(response);

    if (request.method !== "POST") {
      response.setHeader("Allow", "POST");
      sendJSON(response, 405, { error: "지원하지 않는 요청입니다." }, "no-store");
      return;
    }

    try {
      const body = await readJSONBody(request, maximumBodyBytes);
      const result = await handler(body);
      sendJSON(response, 200, result.body, "no-store");
    } catch (error) {
      if (error instanceof HTTPError) {
        sendJSON(response, error.status, { error: error.message }, "no-store");
        return;
      }

      console.error("community_api_request_failed", safeErrorMessage(error));
      sendJSON(response, 502, { error: "외부 정보를 불러오지 못했습니다." }, "no-store");
    }
  };
}

export function requiredQuery(url: URL, name: string, maximumLength: number): string {
  const value = (url.searchParams.get(name) ?? "").trim();
  if (value.length === 0) {
    throw new HTTPError(400, `${name} 값이 필요합니다.`);
  }
  if (value.length > maximumLength) {
    throw new HTTPError(400, `${name} 값이 너무 깁니다.`);
  }
  return value;
}

export function optionalQuery(url: URL, name: string, maximumLength: number): string | undefined {
  const value = (url.searchParams.get(name) ?? "").trim();
  if (value.length === 0) return undefined;
  if (value.length > maximumLength) {
    throw new HTTPError(400, `${name} 값이 너무 깁니다.`);
  }
  return value;
}

export function numberQuery(
  url: URL,
  name: string,
  range: { minimum: number; maximum: number },
): number {
  const rawValue = url.searchParams.get(name);
  const normalizedValue = rawValue?.trim() ?? "";
  const value = normalizedValue.length === 0 ? Number.NaN : Number(normalizedValue);
  if (!Number.isFinite(value) || value < range.minimum || value > range.maximum) {
    throw new HTTPError(400, `${name} 값이 올바르지 않습니다.`);
  }
  return value;
}

export function integerQuery(
  url: URL,
  name: string,
  range: { minimum: number; maximum: number },
): number {
  const value = numberQuery(url, name, range);
  if (!Number.isInteger(value)) {
    throw new HTTPError(400, `${name} 값이 올바르지 않습니다.`);
  }
  return value;
}

export function enumQuery<const T extends readonly string[]>(
  url: URL,
  name: string,
  allowedValues: T,
  fallback: T[number],
): T[number] {
  const value = url.searchParams.get(name);
  if (value === null || value.length === 0) return fallback;
  if (!allowedValues.includes(value)) {
    throw new HTTPError(400, `${name} 값이 올바르지 않습니다.`);
  }
  return value as T[number];
}

export function requiredBodyString(
  body: JSONBody,
  name: string,
  maximumLength: number,
): string {
  const rawValue = body[name];
  const value = typeof rawValue === "string" ? rawValue.trim() : "";
  if (value.length === 0) {
    throw new HTTPError(400, `${name} 값이 필요합니다.`);
  }
  if (value.length > maximumLength) {
    throw new HTTPError(400, `${name} 값이 너무 깁니다.`);
  }
  return value;
}

export function optionalBodyString(
  body: JSONBody,
  name: string,
  maximumLength: number,
): string | undefined {
  const rawValue = body[name];
  if (rawValue === undefined || rawValue === null) return undefined;
  if (typeof rawValue !== "string") {
    throw new HTTPError(400, `${name} 값이 올바르지 않습니다.`);
  }
  const value = rawValue.trim();
  if (value.length === 0) return undefined;
  if (value.length > maximumLength) {
    throw new HTTPError(400, `${name} 값이 너무 깁니다.`);
  }
  return value;
}

export function numberBody(
  body: JSONBody,
  name: string,
  range: { minimum: number; maximum: number },
): number {
  const rawValue = body[name];
  const value = typeof rawValue === "number" ? rawValue : Number.NaN;
  if (!Number.isFinite(value) || value < range.minimum || value > range.maximum) {
    throw new HTTPError(400, `${name} 값이 올바르지 않습니다.`);
  }
  return value;
}

export function integerBody(
  body: JSONBody,
  name: string,
  range: { minimum: number; maximum: number },
): number {
  const value = numberBody(body, name, range);
  if (!Number.isInteger(value)) {
    throw new HTTPError(400, `${name} 값이 올바르지 않습니다.`);
  }
  return value;
}

export function enumBody<const T extends readonly string[]>(
  body: JSONBody,
  name: string,
  allowedValues: T,
  fallback: T[number],
): T[number] {
  const value = body[name];
  if (value === undefined || value === null || value === "") return fallback;
  if (typeof value !== "string" || !allowedValues.includes(value)) {
    throw new HTTPError(400, `${name} 값이 올바르지 않습니다.`);
  }
  return value as T[number];
}

export function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    console.error("community_api_missing_environment", name);
    throw new HTTPError(503, "서버 설정이 아직 완료되지 않았습니다.");
  }
  return value;
}

export async function fetchJSON<T>(
  url: URL,
  init: RequestInit = {},
  timeoutMilliseconds = 7_000,
): Promise<T> {
  const response = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(timeoutMilliseconds),
    headers: {
      Accept: "application/json",
      ...init.headers,
    },
  });

  if (!response.ok) {
    throw new Error(`provider_http_${response.status}`);
  }

  return await response.json() as T;
}

export function cleanText(value: string | null | undefined): string {
  if (!value) return "";

  return decodeHTMLEntities(value.replace(/<[^>]*>/g, " "))
    .replace(/\s+/g, " ")
    .trim();
}

export function safeHTTPURL(value: string | null | undefined): string | undefined {
  if (!value) return undefined;
  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") return undefined;
    if (url.protocol === "http:") url.protocol = "https:";
    return url.toString();
  } catch {
    return undefined;
  }
}

export function integerValue(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value);
  if (typeof value !== "string") return undefined;
  const normalizedValue = value.replaceAll(",", "").trim();
  if (normalizedValue.length === 0) return undefined;
  const parsed = Number(normalizedValue);
  return Number.isFinite(parsed) ? Math.round(parsed) : undefined;
}

function setSecurityHeaders(response: ServerResponse): void {
  response.setHeader("Content-Type", "application/json; charset=utf-8");
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("Referrer-Policy", "no-referrer");
}

function sendJSON(
  response: ServerResponse,
  status: number,
  body: unknown,
  cacheControl: string,
): void {
  response.statusCode = status;
  response.setHeader("Cache-Control", cacheControl);
  response.end(JSON.stringify(body));
}

async function readJSONBody(
  request: IncomingMessage,
  maximumBodyBytes: number,
): Promise<JSONBody> {
  const chunks: Buffer[] = [];
  let byteCount = 0;

  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    byteCount += buffer.byteLength;
    if (byteCount > maximumBodyBytes) {
      throw new HTTPError(413, "요청 내용이 너무 깁니다.");
    }
    chunks.push(buffer);
  }

  if (chunks.length === 0) {
    throw new HTTPError(400, "요청 내용이 필요합니다.");
  }

  try {
    const value: unknown = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new HTTPError(400, "요청 내용이 올바르지 않습니다.");
    }
    return value as JSONBody;
  } catch (error) {
    if (error instanceof HTTPError) throw error;
    throw new HTTPError(400, "요청 내용이 올바르지 않습니다.");
  }
}

function decodeHTMLEntities(value: string): string {
  const namedEntities: Readonly<Record<string, string>> = {
    amp: "&",
    apos: "'",
    gt: ">",
    lt: "<",
    nbsp: " ",
    quot: "\"",
  };

  return value.replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, (match, entity: string) => {
    if (entity.startsWith("#")) {
      const hexadecimal = entity[1]?.toLowerCase() === "x";
      const digits = entity.slice(hexadecimal ? 2 : 1);
      const codePoint = Number.parseInt(digits, hexadecimal ? 16 : 10);
      if (Number.isSafeInteger(codePoint)) {
        try {
          return String.fromCodePoint(codePoint);
        } catch {
          return match;
        }
      }
      return match;
    }
    return namedEntities[entity.toLowerCase()] ?? match;
  });
}

function safeErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message.slice(0, 200);
  return "unknown_error";
}
