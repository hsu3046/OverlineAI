import {
  createPOSTHandler,
  enumBody,
  integerBody,
  optionalBodyString,
  requiredEnvironment,
  requiredBodyString,
} from "../../lib/http.js";
import { searchCommunityArticles } from "../../lib/community.js";
import type { ArticleSource, CommunityArticle, ListResponse } from "../../lib/types.js";

export default createPOSTHandler(async (requestBody) => {
  const title = requiredBodyString(requestBody, "title", 120);
  const author = optionalBodyString(requestBody, "author", 80);
  const source = enumBody(requestBody, "source", ["all", "naver", "daum"] as const, "all");
  const sort = enumBody(requestBody, "sort", ["relevance", "latest"] as const, "relevance");
  const page = requestBody.page === undefined
    ? 1
    : integerBody(requestBody, "page", { minimum: 1, maximum: 5 });

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
    cacheControl: "no-store",
  };
});
