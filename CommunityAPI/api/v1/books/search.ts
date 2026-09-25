import { createPOSTHandler, enumBody, requiredBodyString, requiredEnvironment } from "../../../lib/http.js";
import { searchBookMetadata } from "../../../lib/books.js";
import { searchGoogleBooks } from "../../../lib/providers/google.js";
import { searchOpenLibraryBooks } from "../../../lib/providers/openlibrary.js";
import { searchRakutenBooks } from "../../../lib/providers/rakuten.js";
import { searchYes24Books } from "../../../lib/providers/yes24.js";
import { searchKakaoBooks } from "../../../lib/providers/kakao.js";
import { searchCachedRakutenBooks } from "../../../lib/rakuten-cache.js";

export default createPOSTHandler(async (requestBody) => {
  const query = requiredBodyString(requestBody, "query", 160);
  const language = enumBody(requestBody, "language", ["ko", "ja", "en"] as const, "ko");
  if (language !== "ko") {
    const bridgeConfigured = Boolean(process.env.KNOWAI_RAKUTEN_SEARCH_URL && process.env.BZOGAK_BOOK_BRIDGE_SECRET);
    const rakuten = language === "ja"
      ? bridgeConfigured
        ? await searchCachedRakutenBooks(query).catch(() => undefined) ?? []
        : process.env.RAKUTEN_APPLICATION_ID && process.env.RAKUTEN_ACCESS_KEY
          ? await searchRakutenBooks(
            query,
            process.env.RAKUTEN_APPLICATION_ID,
            process.env.RAKUTEN_ACCESS_KEY,
            process.env.RAKUTEN_API_REFERER ?? "https://bzogak.aib.vote",
          ).catch(() => [])
          : []
      : [];
    if (rakuten.length > 0) {
      return {
        body: { items: rakuten, message: "Rakuten Books", fetchedAt: new Date().toISOString() },
        cacheControl: "no-store",
      };
    }
    const google = process.env.GOOGLE_BOOKS_API_KEY
      ? await searchGoogleBooks(query, language, process.env.GOOGLE_BOOKS_API_KEY).catch(() => [])
      : [];
    const items = google.length > 0 ? google : await searchOpenLibraryBooks(query, language);
    return {
      body: {
        items,
        message: items.length > 0 ? google.length > 0 ? "Google Books" : "Open Library" : language === "ja" ? "本が見つかりませんでした。" : "No books found.",
        fetchedAt: new Date().toISOString(),
      },
      cacheControl: "no-store",
    };
  }
  if (process.env.YES24_API_KEY) {
    const [yes24, kakao] = await Promise.allSettled([
      searchYes24Books(query, process.env.YES24_API_KEY),
      searchKakaoBooks(query, requiredEnvironment("KAKAO_REST_API_KEY"), 2_500),
    ]);
    const items = yes24.status === "fulfilled" && yes24.value.length > 0
      ? yes24.value
      : kakao.status === "fulfilled" ? kakao.value : [];
    if (yes24.status === "rejected" && kakao.status === "rejected") throw yes24.reason;
    return {
      body: { items, message: items.length > 0
        ? yes24.status === "fulfilled" && yes24.value.length > 0 ? "YES24 도서 검색 결과입니다." : "Kakao 도서 검색 결과입니다."
        : "도서 검색 결과가 없습니다.", fetchedAt: new Date().toISOString() },
      cacheControl: "no-store",
    };
  }
  const result = await searchBookMetadata(
    query,
    requiredEnvironment("ALADIN_TTB_KEY"),
    requiredEnvironment("KAKAO_REST_API_KEY"),
  );

  return {
    body: {
      items: result.items,
      message: result.message,
      fetchedAt: new Date().toISOString(),
    },
    cacheControl: "no-store",
  };
});
