import assert from "node:assert/strict";
import { Readable } from "node:stream";
import test from "node:test";

import { resolveBookMetadataResults } from "../.build/lib/books.js";
import { buildBookQuery, mergeArticles } from "../.build/lib/community.js";
import {
  cleanText,
  createPOSTHandler,
  enumBody,
  integerBody,
  integerQuery,
  integerValue,
  numberBody,
  numberQuery,
  requiredBodyString,
  safeHTTPURL,
} from "../.build/lib/http.js";
import {
  data4LibraryKDC,
  data4LibraryLoanDateRange,
  documentsFromData4LibraryResponse,
  normalizePopularLoans,
} from "../.build/lib/providers/data4library.js";
import { aladinBestsellerCategoryID } from "../.build/lib/providers/aladin.js";
import { matchesPlaceCategory, normalizeKakaoPlaces, searchKakaoPlaces } from "../.build/lib/providers/kakao.js";
import { normalizeGoogleBooks, normalizeGooglePlaces } from "../.build/lib/providers/google.js";
import { normalizeOpenLibraryBooks, rankOpenLibraryBooks } from "../.build/lib/providers/openlibrary.js";
import { buildRakutenBookSearchURL, normalizeRakutenBooks } from "../.build/lib/providers/rakuten.js";
import { normalizeYes24Books } from "../.build/lib/providers/yes24.js";
import { searchCachedRakutenBooks } from "../.build/lib/rakuten-cache.js";
import rankingsHandler from "../.build/api/v1/rankings.js";
import searchBooksHandler from "../.build/api/v1/books/search.js";
import { buildNaverBlogRequest } from "../.build/lib/providers/naver.js";

test("cleanText strips provider markup and decodes entities", () => {
  assert.equal(cleanText("<b>바람</b>&nbsp;의 노래 &amp; 기억"), "바람 의 노래 & 기억");
});

test("safeHTTPURL upgrades http and rejects unsupported schemes", () => {
  assert.equal(safeHTTPURL("http://example.com/book"), "https://example.com/book");
  assert.equal(safeHTTPURL("javascript:alert(1)"), undefined);
});

test("Google Books keeps Japanese metadata and prefers ISBN-13", () => {
  const books = normalizeGoogleBooks({ items: [{
    id: "volume-1",
    volumeInfo: {
      title: "日本語の本",
      authors: ["作家"],
      industryIdentifiers: [
        { type: "ISBN_10", identifier: "1234567890" },
        { type: "ISBN_13", identifier: "9781234567890" },
      ],
      imageLinks: { thumbnail: "http://example.com/cover.jpg" },
    },
  }] });
  assert.equal(books[0].source, "google");
  assert.equal(books[0].title, "日本語の本");
  assert.equal(books[0].isbn, "9781234567890");
  assert.match(books[0].coverURLString, /^https:/);
});

test("Rakuten Books searches ISBN directly and includes unavailable editions", () => {
  const isbnURL = buildRakutenBookSearchURL("978-4-00-310101-8", "app-id");
  assert.equal(isbnURL.searchParams.get("isbn"), "9784003101018");
  assert.equal(isbnURL.searchParams.get("title"), null);
  assert.equal(isbnURL.searchParams.get("outOfStockFlag"), "1");
  assert.equal(isbnURL.searchParams.get("formatVersion"), "2");

  const titleURL = buildRakutenBookSearchURL("吾輩は猫である", "app-id");
  assert.equal(titleURL.searchParams.get("title"), "吾輩は猫である");
  assert.equal(titleURL.searchParams.get("isbn"), null);
  assert.equal(titleURL.searchParams.get("accessKey"), null);
});

test("Rakuten Books maps Japanese metadata from flat and wrapped responses", () => {
  const item = {
    title: "<b>吾輩は猫である</b>",
    author: "夏目漱石",
    publisherName: "岩波書店",
    salesDate: "2026年09月",
    itemCaption: "日本文学 &amp; 小説",
    isbn: "9784003101018",
    largeImageUrl: "http://example.com/cover.jpg",
  };
  for (const response of [{ Items: [item] }, { Items: [{ Item: item }] }]) {
    const [book] = normalizeRakutenBooks(response);
    assert.equal(book.source, "rakuten");
    assert.equal(book.title, "吾輩は猫である");
    assert.equal(book.summary, "日本文学 & 小説");
    assert.equal(book.publishedDate, "2026年09月");
    assert.equal(book.coverURLString, "https://example.com/cover.jpg");
  }
  assert.deepEqual(normalizeRakutenBooks({ Items: [{ title: "ISBN 없음" }] }), []);
});

test("YES24 book search maps source, detail link, and ISBN without adult items", () => {
  const books = normalizeYes24Books({ data: { items: [
    { itemId: 41, title: "책", author: "작가", isbn13: "9781234567890", isbn10: "1234567890",
      link: "https://www.yes24.com/product/goods/41", adultYn: "N" },
    { itemId: 42, title: "성인 도서", adultYn: "Y" },
    { itemId: 43, title: "구판", isbn10: "123456789X" },
  ] } });
  assert.equal(books.length, 2);
  assert.equal(books[0].source, "yes24");
  assert.equal(books[0].detailURL, "https://www.yes24.com/product/goods/41");
  assert.equal(books[0].isbn, "9781234567890");
  assert.equal(books[1].isbn, "123456789X");
});

test("ranking snapshot serves page 2 from one 100-item cache without calling providers", async () => {
  const originalFetch = globalThis.fetch;
  const previousURL = process.env.KNOWAI_RANKING_CACHE_URL;
  const previousSecret = process.env.BZOGAK_BOOK_BRIDGE_SECRET;
  process.env.KNOWAI_RANKING_CACHE_URL = "https://www.aib.vote/api/x/bzogak-rankings";
  process.env.BZOGAK_BOOK_BRIDGE_SECRET = "test-secret";
  const fetchedAt = new Date().toISOString();
  const requested = [];
  globalThis.fetch = async (input, options) => {
    const url = new URL(String(input));
    requested.push(url);
    assert.equal(url.host, "www.aib.vote");
    assert.equal(options.headers["x-bzogak-bridge-secret"], "test-secret");
    return Response.json({
      fetchedAt,
      items: Array.from({ length: 100 }, (_, index) => ({
        id: `yes24-${index + 1}`, rank: index + 1,
        title: `책 ${index + 1}`, author: "작가", source: "yes24",
      })),
    });
  };
  try {
    const request = { method: "GET", url: "/api/v1/rankings?kind=bestseller&category=all&page=2",
      headers: { host: "localhost" } };
    let responseBody = "";
    const response = { statusCode: 0, setHeader() {}, end(value = "") { responseBody = String(value); } };
    await rankingsHandler(request, response);
    const body = JSON.parse(responseBody);
    assert.equal(response.statusCode, 200);
    assert.equal(body.items.length, 20);
    assert.equal(body.items[0].rank, 21);
    assert.equal(body.fetchedAt, fetchedAt);
    assert.equal(requested.length, 1);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of [
      ["KNOWAI_RANKING_CACHE_URL", previousURL],
      ["BZOGAK_BOOK_BRIDGE_SECRET", previousSecret],
    ]) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("Japanese rankings use the Rakuten snapshot and never show Korean books", async () => {
  const originalFetch = globalThis.fetch;
  const previousURL = process.env.KNOWAI_RANKING_CACHE_URL;
  const previousSecret = process.env.BZOGAK_BOOK_BRIDGE_SECRET;
  process.env.KNOWAI_RANKING_CACHE_URL = "https://www.aib.vote/api/x/bzogak-rankings";
  process.env.BZOGAK_BOOK_BRIDGE_SECRET = "test-secret";
  const requested = [];
  globalThis.fetch = async (input) => {
    const url = new URL(String(input));
    requested.push(url);
    assert.equal(url.searchParams.get("source"), "rakuten");
    assert.equal(url.searchParams.get("category"), "fiction");
    return Response.json({ fetchedAt: new Date().toISOString(), items: [{
      id: "rakuten-9784003101018", rank: 1, title: "日本語の本", author: "作家", source: "rakuten",
    }] });
  };
  try {
    const request = { method: "GET", url: "/api/v1/rankings?language=ja&kind=bestseller&category=fiction",
      headers: { host: "localhost" } };
    let responseBody = "";
    const response = { statusCode: 0, setHeader() {}, end(value = "") { responseBody = String(value); } };
    await rankingsHandler(request, response);
    assert.equal(response.statusCode, 200);
    assert.equal(JSON.parse(responseBody).items[0].source, "rakuten");
    assert.equal(requested.length, 1);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of [["KNOWAI_RANKING_CACHE_URL", previousURL], ["BZOGAK_BOOK_BRIDGE_SECRET", previousSecret]]) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("Japanese rankings reject loans and never fall back to Korean bestsellers", async () => {
  const previousURL = process.env.KNOWAI_RANKING_CACHE_URL;
  const previousSecret = process.env.BZOGAK_BOOK_BRIDGE_SECRET;
  delete process.env.KNOWAI_RANKING_CACHE_URL;
  delete process.env.BZOGAK_BOOK_BRIDGE_SECRET;
  try {
    for (const url of [
      "/api/v1/rankings?language=ja&kind=loans",
      "/api/v1/rankings?language=ja&kind=bestseller",
    ]) {
      const request = { method: "GET", url, headers: { host: "localhost" } };
      const response = { statusCode: 0, setHeader() {}, end() {} };
      await rankingsHandler(request, response);
      assert.equal(response.statusCode, url.includes("loans") ? 400 : 503);
    }
  } finally {
    for (const [key, value] of [["KNOWAI_RANKING_CACHE_URL", previousURL], ["BZOGAK_BOOK_BRIDGE_SECRET", previousSecret]]) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("an unseeded ranking snapshot keeps the existing loan provider available", async () => {
  const originalFetch = globalThis.fetch;
  const previous = {
    url: process.env.KNOWAI_RANKING_CACHE_URL,
    secret: process.env.BZOGAK_BOOK_BRIDGE_SECRET,
    key: process.env.DATA4LIBRARY_AUTH_KEY,
  };
  process.env.KNOWAI_RANKING_CACHE_URL = "https://www.aib.vote/api/x/bzogak-rankings";
  process.env.BZOGAK_BOOK_BRIDGE_SECRET = "test-secret";
  process.env.DATA4LIBRARY_AUTH_KEY = "test-library-key";
  const hosts = [];
  globalThis.fetch = async (input) => {
    const url = new URL(String(input));
    hosts.push(url.host);
    if (url.host === "www.aib.vote") return Response.json({ error: "snapshot_missing" }, { status: 404 });
    if (url.host === "data4library.kr") {
      return Response.json({ response: { docs: [{ doc: {
        ranking: "1", bookname: "책", authors: "작가", isbn13: "9781234567890",
      } }] } });
    }
    throw new Error(`Unexpected host: ${url.host}`);
  };
  try {
    const request = { method: "GET", url: "/api/v1/rankings?kind=loans&page=1",
      headers: { host: "localhost" } };
    let result = "";
    const response = { statusCode: 0, setHeader() {}, end(value = "") { result = String(value); } };
    await rankingsHandler(request, response);
    assert.equal(response.statusCode, 200);
    assert.equal(JSON.parse(result).items[0].source, "data4library");
    assert.deepEqual(hosts, ["www.aib.vote", "data4library.kr"]);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of [
      ["KNOWAI_RANKING_CACHE_URL", previous.url],
      ["BZOGAK_BOOK_BRIDGE_SECRET", previous.secret],
      ["DATA4LIBRARY_AUTH_KEY", previous.key],
    ]) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("a broken ranking bridge never fans out into provider calls", async () => {
  const originalFetch = globalThis.fetch;
  const previousURL = process.env.KNOWAI_RANKING_CACHE_URL;
  const previousSecret = process.env.BZOGAK_BOOK_BRIDGE_SECRET;
  process.env.KNOWAI_RANKING_CACHE_URL = "https://www.aib.vote/api/x/bzogak-rankings";
  process.env.BZOGAK_BOOK_BRIDGE_SECRET = "test-secret";
  const hosts = [];
  globalThis.fetch = async (input) => {
    const url = new URL(String(input));
    hosts.push(url.host);
    return Response.json({ error: "cache_unavailable" }, { status: 503 });
  };
  try {
    const request = { method: "GET", url: "/api/v1/rankings?kind=bestseller",
      headers: { host: "localhost" } };
    let result = "";
    const response = { statusCode: 0, setHeader() {}, end(value = "") { result = String(value); } };
    await rankingsHandler(request, response);
    assert.equal(response.statusCode, 502);
    assert.equal(JSON.parse(result).error, "외부 정보를 불러오지 못했습니다.");
    assert.deepEqual(hosts, ["www.aib.vote"]);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of [
      ["KNOWAI_RANKING_CACHE_URL", previousURL],
      ["BZOGAK_BOOK_BRIDGE_SECRET", previousSecret],
    ]) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("pending Rakuten bridge uses Open Library without a direct Rakuten call", async () => {
  const originalFetch = globalThis.fetch;
  const previousURL = process.env.KNOWAI_RAKUTEN_SEARCH_URL;
  const previousSecret = process.env.BZOGAK_BOOK_BRIDGE_SECRET;
  const previousGoogle = process.env.GOOGLE_BOOKS_API_KEY;
  process.env.KNOWAI_RAKUTEN_SEARCH_URL = "https://www.aib.vote/api/x/bzogak-book-search";
  process.env.BZOGAK_BOOK_BRIDGE_SECRET = "test-secret";
  delete process.env.GOOGLE_BOOKS_API_KEY;
  const hosts = [];
  globalThis.fetch = async (input) => {
    const url = new URL(String(input));
    hosts.push(url.host);
    if (url.host === "www.aib.vote") return Response.json({ status: "pending" }, { status: 202 });
    if (url.host === "openlibrary.org") {
      return Response.json({ docs: [{ key: "/works/OL1W", title: "吾輩は猫である",
        isbn: ["9784003101018"] }] });
    }
    throw new Error(`Unexpected host: ${url.host}`);
  };
  try {
    const request = Readable.from([Buffer.from(JSON.stringify({ query: "吾輩は猫である", language: "ja" }))]);
    request.method = "POST";
    request.headers = { host: "localhost" };
    let result = "";
    const response = { statusCode: 0, setHeader() {}, end(value = "") { result = String(value); } };
    await searchBooksHandler(request, response);
    assert.equal(response.statusCode, 200);
    assert.equal(JSON.parse(result).items[0].source, "openLibrary");
    assert.deepEqual(hosts, ["www.aib.vote", "openlibrary.org"]);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of [
      ["KNOWAI_RAKUTEN_SEARCH_URL", previousURL],
      ["BZOGAK_BOOK_BRIDGE_SECRET", previousSecret],
      ["GOOGLE_BOOKS_API_KEY", previousGoogle],
    ]) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("Rakuten cache rejects incomplete book metadata and invalid detail URLs", async () => {
  const originalFetch = globalThis.fetch;
  const previousURL = process.env.KNOWAI_RAKUTEN_SEARCH_URL;
  const previousSecret = process.env.BZOGAK_BOOK_BRIDGE_SECRET;
  process.env.KNOWAI_RAKUTEN_SEARCH_URL = "https://www.aib.vote/api/x/bzogak-book-search";
  process.env.BZOGAK_BOOK_BRIDGE_SECRET = "test-secret";
  const complete = {
    source: "rakuten", id: "book-1", title: "本", author: "著者", summary: "",
    publisher: "出版社", publishedDate: "", isbn: "9784003101018", coverURLString: "",
  };
  try {
    for (const field of ["summary", "publisher", "publishedDate", "coverURLString"]) {
      const invalid = { ...complete };
      delete invalid[field];
      globalThis.fetch = async () => Response.json({ items: [invalid] });
      await assert.rejects(searchCachedRakutenBooks("本"), /invalid_rakuten_cache/);
    }
    globalThis.fetch = async () => Response.json({ items: [{ ...complete, detailURL: 42 }] });
    await assert.rejects(searchCachedRakutenBooks("本"), /invalid_rakuten_cache/);
    globalThis.fetch = async () => Response.json({ items: [complete] });
    assert.equal((await searchCachedRakutenBooks("本"))[0].id, "book-1");
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of [
      ["KNOWAI_RAKUTEN_SEARCH_URL", previousURL],
      ["BZOGAK_BOOK_BRIDGE_SECRET", previousSecret],
    ]) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("Japanese book search falls back when Rakuten denies access", async () => {
  const originalFetch = globalThis.fetch;
  const originalApplicationID = process.env.RAKUTEN_APPLICATION_ID;
  const originalAccessKey = process.env.RAKUTEN_ACCESS_KEY;
  const originalGoogleKey = process.env.GOOGLE_BOOKS_API_KEY;
  process.env.RAKUTEN_APPLICATION_ID = "test-app";
  process.env.RAKUTEN_ACCESS_KEY = "test-key";
  delete process.env.GOOGLE_BOOKS_API_KEY;
  const calledHosts = [];
  globalThis.fetch = async (input) => {
    const url = new URL(String(input));
    calledHosts.push(url.host);
    if (url.host === "openapi.rakuten.co.jp") return new Response("denied", { status: 403 });
    if (url.host === "openlibrary.org") {
      return Response.json({ docs: [{ key: "/works/OL1W", title: "吾輩は猫である", isbn: ["9784003101018"] }] });
    }
    throw new Error(`Unexpected host: ${url.host}`);
  };
  try {
    const request = Readable.from([Buffer.from(JSON.stringify({ query: "吾輩は猫である", language: "ja" }))]);
    request.method = "POST";
    request.headers = { host: "localhost" };
    let result = "";
    const response = { statusCode: 0, setHeader() {}, end(value = "") { result = String(value); } };
    await searchBooksHandler(request, response);
    const body = JSON.parse(result);
    assert.equal(response.statusCode, 200);
    assert.deepEqual(calledHosts, ["openapi.rakuten.co.jp", "openlibrary.org"]);
    assert.equal(body.items[0].source, "openLibrary");
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of [
      ["RAKUTEN_APPLICATION_ID", originalApplicationID],
      ["RAKUTEN_ACCESS_KEY", originalAccessKey],
      ["GOOGLE_BOOKS_API_KEY", originalGoogleKey],
    ]) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("Google Places maps type, distance, and Maps URL", () => {
  const places = normalizeGooglePlaces({ places: [{
    id: "place-1",
    displayName: { text: "市立図書館" },
    primaryType: "library",
    formattedAddress: "東京都千代田区",
    location: { latitude: 35.0005, longitude: 139 },
    googleMapsUri: "https://maps.google.com/?cid=1",
  }] }, 35, 139, "all");
  assert.equal(places[0].kind, "library");
  assert.equal(places[0].source, "google");
  assert.ok(places[0].distanceMeters > 0);
  assert.match(places[0].detailURL, /maps.google.com/);
});

test("Open Library fallback maps title, cover, and ISBN", () => {
  const books = normalizeOpenLibraryBooks({ docs: [{
    key: "/works/OL123W",
    title: "吾輩は猫である",
    author_name: ["夏目漱石"],
    isbn: ["1234567890", "9781234567890"],
    cover_i: 42,
  }] });
  assert.equal(books[0].source, "openLibrary");
  assert.equal(books[0].isbn, "9781234567890");
  assert.equal(books[0].coverURLString, "https://covers.openlibrary.org/b/id/42-M.jpg");
});

test("Open Library prioritizes the exact Japanese title over related essays", () => {
  const candidates = normalizeOpenLibraryBooks({ docs: [
    { key: "/works/essay", title: "『吾輩は猫である』下篇自序" },
    { key: "/works/book", title: "吾輩は猫である" },
  ] });
  assert.equal(rankOpenLibraryBooks(candidates, "吾輩は猫である")[0].id, "openlibrary-/works/book");
});

test("numeric parsing rejects explicitly empty values", () => {
  const url = new URL("https://example.com/places?lat=&lng=%20");
  assert.throws(() => numberQuery(url, "lat", { minimum: -90, maximum: 90 }));
  assert.throws(() => numberQuery(url, "lng", { minimum: -180, maximum: 180 }));
  assert.equal(integerValue(""), undefined);
  assert.equal(integerValue("  "), undefined);
});

test("integer query rejects fractional pagination values", () => {
  const fractional = new URL("https://example.com/articles?page=1.5");
  const valid = new URL("https://example.com/articles?page=2");
  assert.throws(() => integerQuery(fractional, "page", { minimum: 1, maximum: 5 }));
  assert.equal(integerQuery(valid, "page", { minimum: 1, maximum: 5 }), 2);
});

test("private search request bodies are validated without URL query values", () => {
  const body = {
    latitude: 37.5665,
    longitude: 126.978,
    radius: 5000,
    kind: "library",
    title: "바람의 노래를 들어라",
  };

  assert.equal(numberBody(body, "latitude", { minimum: -90, maximum: 90 }), 37.5665);
  assert.equal(integerBody(body, "radius", { minimum: 500, maximum: 20_000 }), 5000);
  assert.equal(enumBody(body, "kind", ["all", "bookstore", "library"], "all"), "library");
  assert.equal(requiredBodyString(body, "title", 120), "바람의 노래를 들어라");
  assert.throws(() => integerBody({ radius: 500.5 }, "radius", { minimum: 500, maximum: 20_000 }));
});

test("private search handler accepts JSON POST and always disables caching", async () => {
  const handler = createPOSTHandler(async (body) => ({ body: { title: body.title } }));
  const request = Readable.from([Buffer.from('{"title":"테스트"}')]);
  request.method = "POST";
  request.headers = { host: "example.com" };

  const headers = new Map();
  let responseBody = "";
  const response = {
    statusCode: 0,
    setHeader(name, value) {
      headers.set(name, value);
    },
    end(value = "") {
      responseBody = String(value);
    },
  };

  await handler(request, response);

  assert.equal(response.statusCode, 200);
  assert.equal(headers.get("Cache-Control"), "no-store");
  assert.deepEqual(JSON.parse(responseBody), { title: "테스트" });
});

test("Kakao places require a usable address and distance", () => {
  const places = normalizeKakaoPlaces([
    {
      id: "1",
      place_name: "동네 서점",
      category_name: "문화,예술 > 도서 > 서점",
      road_address_name: "서울시 어딘가 1",
      distance: "420",
      place_url: "http://place.map.kakao.com/1",
    },
    { id: "2", place_name: "주소 없는 곳", distance: "10" },
    {
      id: "3",
      place_name: "서점 이름이 들어간 카페",
      category_name: "음식점 > 카페 > 커피전문점",
      road_address_name: "서울시 어딘가 2",
      distance: "30",
    },
  ], "bookstore");

  assert.equal(places.length, 1);
  assert.equal(places[0]?.distanceMeters, 420);
  assert.equal(places[0]?.detailURL, "https://place.map.kakao.com/1");
});

test("place category matching excludes keyword-only businesses", () => {
  assert.equal(matchesPlaceCategory("문화,예술 > 도서 > 서점 > 교보문고", "bookstore"), true);
  assert.equal(matchesPlaceCategory("음식점 > 카페 > 커피전문점", "bookstore"), false);
  assert.equal(matchesPlaceCategory("교육,학문 > 학습시설 > 도서관 > 작은도서관", "library"), true);
  assert.equal(matchesPlaceCategory("교육,학문 > 학교부속시설", "library"), false);
});

test("Kakao all-kind place search marks one-provider results as incomplete", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    const url = new URL(String(input));
    if (url.searchParams.get("query") === "도서관") {
      return new Response("unavailable", { status: 503 });
    }
    return Response.json({
      documents: [{
        id: "bookstore-1",
        place_name: "동네 서점",
        category_name: "문화,예술 > 도서 > 서점",
        road_address_name: "서울시 어딘가 1",
        distance: "100",
      }],
      meta: { is_end: true, pageable_count: 1 },
    });
  };

  try {
    const result = await searchKakaoPlaces(37.5, 127, 5_000, "all", "test-key");
    assert.equal(result.items.length, 1);
    assert.equal(result.isComplete, false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("loan rankings preserve provider rank and count", () => {
  const items = normalizePopularLoans([{
    doc: {
      ranking: "2",
      bookname: "책 이름",
      authors: "저자",
      isbn13: "9780000000000",
      loan_count: "1,234",
    },
  }], 1);

  assert.equal(items[0]?.rank, 2);
  assert.equal(items[0]?.loanCount, 1234);
});

test("data4library provider errors are not treated as an empty ranking", () => {
  assert.throws(
    () => documentsFromData4LibraryResponse({ response: { errCode: "AUTH", error: "not active" } }),
    /data4library_provider_error_AUTH/,
  );
});

test("loan ranking dates use the Korean calendar before 09:00 KST", () => {
  assert.deepEqual(
    data4LibraryLoanDateRange(new Date("2026-08-30T00:30:00+09:00")),
    { startDate: "2026-07-31", endDate: "2026-08-29" },
  );
});

test("ranking categories map to provider category identifiers", () => {
  assert.equal(aladinBestsellerCategoryID("essay"), "55889");
  assert.equal(aladinBestsellerCategoryID("all"), undefined);
  assert.equal(data4LibraryKDC("literature"), "8");
  assert.equal(data4LibraryKDC("all"), undefined);
});

test("article query uses the stored book and author", () => {
  assert.equal(buildBookQuery("[개정판] 바람의 노래", "무라카미 하루키"), "개정판 바람의 노래 무라카미 하루키 책");
  assert.equal(buildBookQuery("어린 왕자", "Unknown"), "어린 왕자 책");
});

test("book metadata fallback is incomplete when Aladin is unavailable", () => {
  const kakaoItem = {
    id: "kakao-book",
    title: "책",
    author: "저자",
    summary: "",
    publisher: "출판사",
    publishedDate: "",
    isbn: "",
    coverURLString: "",
    source: "kakao",
  };
  const result = resolveBookMetadataResults(
    { status: "rejected", reason: new Error("timeout") },
    { status: "fulfilled", value: [kakaoItem] },
  );

  assert.deepEqual(result.items, [kakaoItem]);
  assert.equal(result.isComplete, false);
});

test("relevance results alternate sources", () => {
  const item = (id, source, date) => ({
    id,
    title: id,
    snippet: "",
    url: `https://example.com/${id}`,
    source,
    sourceName: source,
    publishedAt: date,
  });
  const items = mergeArticles([
    [item("n1", "naver", "2026-01-01"), item("n2", "naver", "2026-01-03")],
    [item("d1", "daum", "2026-01-02")],
  ], "relevance");

  assert.deepEqual(items.map((entry) => entry.id), ["n1", "d1", "n2"]);
});

test("NAVER blog search uses the Developers API credentials", () => {
  const request = buildNaverBlogRequest("소년이 온다", "relevance", 2, "client-id", "client-secret");

  assert.equal(request.url.origin, "https://openapi.naver.com");
  assert.equal(request.url.pathname, "/v1/search/blog.json");
  assert.equal(request.url.searchParams.get("start"), "21");
  assert.deepEqual(request.init.headers, {
    "X-Naver-Client-Id": "client-id",
    "X-Naver-Client-Secret": "client-secret",
  });
});
