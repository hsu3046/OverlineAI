import assert from "node:assert/strict";
import test from "node:test";

import { buildBookQuery, mergeArticles } from "../.build/lib/community.js";
import { cleanText, safeHTTPURL } from "../.build/lib/http.js";
import {
  data4LibraryKDC,
  data4LibraryLoanDateRange,
  documentsFromData4LibraryResponse,
  normalizePopularLoans,
} from "../.build/lib/providers/data4library.js";
import { aladinBestsellerCategoryID } from "../.build/lib/providers/aladin.js";
import { matchesPlaceCategory, normalizeKakaoPlaces } from "../.build/lib/providers/kakao.js";
import { buildNaverBlogRequest } from "../.build/lib/providers/naver.js";

test("cleanText strips provider markup and decodes entities", () => {
  assert.equal(cleanText("<b>바람</b>&nbsp;의 노래 &amp; 기억"), "바람 의 노래 & 기억");
});

test("safeHTTPURL upgrades http and rejects unsupported schemes", () => {
  assert.equal(safeHTTPURL("http://example.com/book"), "https://example.com/book");
  assert.equal(safeHTTPURL("javascript:alert(1)"), undefined);
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
