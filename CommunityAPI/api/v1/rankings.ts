import { createGETHandler, enumQuery, HTTPError, integerQuery, requiredEnvironment } from "../../lib/http.js";
import { fetchAladinBestsellers } from "../../lib/providers/aladin.js";
import { fetchPopularLoans } from "../../lib/providers/data4library.js";
import { readRankingSnapshot } from "../../lib/ranking-snapshot.js";
import type { CommunityRankingItem, ListResponse } from "../../lib/types.js";

const bestsellerCategories = [
  "all", "fiction", "essay", "humanities", "business", "selfDevelopment", "children",
] as const;
const loanCategories = [
  "all", "literature", "philosophy", "socialScience", "naturalScience", "technology", "arts", "history",
] as const;

export default createGETHandler(async (url) => {
  const language = enumQuery(url, "language", ["ko", "ja", "en"] as const, "ko");
  const kind = enumQuery(url, "kind", ["bestseller", "loans"] as const, "bestseller");
  if (language === "ja" && kind === "loans") {
    throw new HTTPError(400, "日本の貸出ランキングは提供していません。");
  }
  const page = url.searchParams.has("page")
    ? integerQuery(url, "page", { minimum: 1, maximum: 5 })
    : 1;

  const category = kind === "bestseller"
    ? enumQuery(url, "category", bestsellerCategories, "all")
    : enumQuery(url, "category", loanCategories, "all");
  const source = kind === "loans" ? "data4library" : language === "ja" ? "rakuten" : "yes24";
  const snapshot = await readRankingSnapshot(source, category);
  if (snapshot) {
    const first = (page - 1) * 20;
    return {
      body: { items: snapshot.items.slice(first, first + 20), fetchedAt: snapshot.fetchedAt },
      cacheControl: "public, s-maxage=21600, stale-while-revalidate=86400",
    };
  }

  // Never show Korean books or call Rakuten from Vercel when the Japanese cache is missing.
  if (language === "ja") {
    throw new HTTPError(503, "楽天ブックスの売れ筋データを準備中です。");
  }

  // Rollout fallback only: before the manual SQL and first sync, existing rankings stay live.
  const items = kind === "bestseller"
    ? await fetchAladinBestsellers(
      page,
      requiredEnvironment("ALADIN_TTB_KEY"),
      category as (typeof bestsellerCategories)[number],
    )
    : await fetchPopularLoans(
      page,
      requiredEnvironment("DATA4LIBRARY_AUTH_KEY"),
      category as (typeof loanCategories)[number],
    );
  const body: ListResponse<CommunityRankingItem> = {
    items,
    fetchedAt: new Date().toISOString(),
  };

  return {
    body,
    cacheControl: "public, s-maxage=21600, stale-while-revalidate=86400",
  };
});
