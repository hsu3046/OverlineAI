import {
  createGETHandler,
  enumQuery,
  integerQuery,
  optionalQuery,
  requiredEnvironment,
  requiredQuery,
} from "../../lib/http.js";
import { searchCommunityArticles } from "../../lib/community.js";
import type { ArticleSource, CommunityArticle, ListResponse } from "../../lib/types.js";

export default createGETHandler(async (url) => {
  const title = requiredQuery(url, "title", 120);
  const author = optionalQuery(url, "author", 80);
  const source = enumQuery(url, "source", ["all", "naver", "daum"] as const, "all");
  const sort = enumQuery(url, "sort", ["relevance", "latest"] as const, "relevance");
  const page = url.searchParams.has("page")
    ? integerQuery(url, "page", { minimum: 1, maximum: 5 })
    : 1;

  const result = await searchCommunityArticles({
    title,
    ...(author ? { author } : {}),
    source: source as ArticleSource | "all",
    sort,
    page,
    kakaoAPIKey: requiredEnvironment("KAKAO_REST_API_KEY"),
    naverClientID: requiredEnvironment("NAVER_CLIENT_ID"),
    naverClientSecret: requiredEnvironment("NAVER_CLIENT_SECRET"),
  });
  const body: ListResponse<CommunityArticle> = {
    items: result.items,
    fetchedAt: new Date().toISOString(),
    ...(result.warnings.length > 0 ? { warnings: result.warnings } : {}),
  };

  return {
    body,
    cacheControl: result.warnings.length === 0
      ? "public, s-maxage=1800, stale-while-revalidate=3600"
      : "no-store",
  };
});
