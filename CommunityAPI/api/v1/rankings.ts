import { createGETHandler, enumQuery, integerQuery, requiredEnvironment } from "../../lib/http.js";
import { fetchAladinBestsellers } from "../../lib/providers/aladin.js";
import { fetchPopularLoans } from "../../lib/providers/data4library.js";
import type { CommunityRankingItem, ListResponse } from "../../lib/types.js";

const bestsellerCategories = [
  "all", "fiction", "essay", "humanities", "business", "selfDevelopment", "children",
] as const;
const loanCategories = [
  "all", "literature", "philosophy", "socialScience", "naturalScience", "technology", "arts", "history",
] as const;

export default createGETHandler(async (url) => {
  const kind = enumQuery(url, "kind", ["bestseller", "loans"] as const, "bestseller");
  const page = url.searchParams.has("page")
    ? integerQuery(url, "page", { minimum: 1, maximum: 5 })
    : 1;

  const items = kind === "bestseller"
    ? await fetchAladinBestsellers(
      page,
      requiredEnvironment("ALADIN_TTB_KEY"),
      enumQuery(url, "category", bestsellerCategories, "all"),
    )
    : await fetchPopularLoans(
      page,
      requiredEnvironment("DATA4LIBRARY_AUTH_KEY"),
      enumQuery(url, "category", loanCategories, "all"),
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
