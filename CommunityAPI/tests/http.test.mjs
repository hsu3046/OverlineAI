import assert from "node:assert/strict";
import { Readable } from "node:stream";
import test from "node:test";

import { createPOSTHandler } from "../.build/lib/http.js";

function requestWithBody(body) {
  const request = Readable.from([]);
  request.method = "POST";
  request.headers = { "content-type": "application/json" };
  request.body = body;
  return request;
}

async function invoke(request, limit = 8_192) {
  const headers = new Map();
  let responseBody;
  let calls = 0;
  const response = {
    statusCode: 0,
    setHeader(name, value) { headers.set(name, value); },
    end(value) { responseBody = JSON.parse(value); },
  };
  await createPOSTHandler(async (body) => {
    calls += 1;
    return { body };
  }, limit)(request, response);
  assert.equal(headers.get("Cache-Control"), "no-store");
  return { status: response.statusCode, body: responseBody, calls, headers };
}

test("Vercel parsed JSON is used after the request stream has ended", async () => {
  const body = { title: "책 이름", latitude: 37.5, page: 1 };
  const request = requestWithBody(body);
  for await (const _ of request) { /* Simulate the runtime consuming the stream. */ }
  assert.equal(request.readableEnded, true);
  const result = await invoke(request);
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, body);
  assert.equal(result.calls, 1);
});

test("parsed JSON does not read or merge the underlying stream", async () => {
  const request = requestWithBody({ title: "Parsed title" });
  request[Symbol.asyncIterator] = () => { throw new Error("Stream must not be read"); };
  const result = await invoke(request);
  assert.equal(result.status, 200);
  assert.equal(result.body.title, "Parsed title");
});

test("parsed JSON uses UTF-8 byte limits at the exact boundary", async () => {
  const body = { title: "가나다" };
  const bytes = Buffer.byteLength(JSON.stringify(body));
  assert.equal((await invoke(requestWithBody(body), bytes)).status, 200);
  const tooLarge = await invoke(requestWithBody(body), bytes - 1);
  assert.equal(tooLarge.status, 413);
  assert.equal(tooLarge.calls, 0);
});

test("declared wire size also limits parsed bodies with whitespace or escapes", async () => {
  const request = requestWithBody({ title: "a" });
  request.headers["content-length"] = "8193";
  const result = await invoke(request);
  assert.equal(result.status, 413);
  assert.equal(result.calls, 0);
});

test("parsed arrays, null, scalars and binary bodies are rejected", async () => {
  for (const body of [null, [], false, 1, "{\"title\":\"nested\"}", Buffer.from("{}")]) {
    const result = await invoke(requestWithBody(body));
    assert.equal(result.status, 400);
    assert.equal(result.calls, 0);
  }
});

test("a lazy runtime JSON parse failure is a client error", async () => {
  const request = requestWithBody(undefined);
  Object.defineProperty(request, "body", { get() { throw new SyntaxError("Invalid JSON"); } });
  const result = await invoke(request);
  assert.equal(result.status, 400);
  assert.equal(result.calls, 0);
});

test("unparsed streams keep validation and byte limits", async () => {
  for (const [chunks, limit, expected] of [
    [[Buffer.from('{"title":'), Buffer.from('"책"}')], 8192, 200],
    [[Buffer.from('{"title":"책"}')], 10, 413],
    [[Buffer.from("{")], 8192, 400],
    [[Buffer.from("[]")], 8192, 400],
    [[], 8192, 400],
  ]) {
    const request = Readable.from(chunks);
    request.method = "POST";
    request.headers = {};
    request.body = undefined;
    const result = await invoke(request, limit);
    assert.equal(result.status, expected);
    assert.equal(result.calls, expected === 200 ? 1 : 0);
  }
});

test("method rejection still occurs before reading the parsed body", async () => {
  const request = requestWithBody({ title: "Book" });
  request.method = "GET";
  const result = await invoke(request);
  assert.equal(result.status, 405);
  assert.equal(result.headers.get("Allow"), "POST");
  assert.equal(result.calls, 0);
});
