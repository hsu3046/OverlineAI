import { createGETHandler, enumQuery, integerQuery, numberQuery, requiredEnvironment } from "../../lib/http.js";
import { searchKakaoPlaces } from "../../lib/providers/kakao.js";
import type { ListResponse, PlaceKind, CommunityPlace } from "../../lib/types.js";

export default createGETHandler(async (url) => {
  const latitude = numberQuery(url, "lat", { minimum: -90, maximum: 90 });
  const longitude = numberQuery(url, "lng", { minimum: -180, maximum: 180 });
  const radius = url.searchParams.has("radius")
    ? integerQuery(url, "radius", { minimum: 500, maximum: 20_000 })
    : 5_000;
  const kind = enumQuery(url, "kind", ["all", "bookstore", "library"] as const, "all");
  const apiKey = requiredEnvironment("KAKAO_REST_API_KEY");
  const result = await searchKakaoPlaces(latitude, longitude, radius, kind as PlaceKind | "all", apiKey);
  const body: ListResponse<CommunityPlace> = {
    items: result.items,
    fetchedAt: new Date().toISOString(),
    ...(!result.isComplete ? { warnings: ["kakao_partial_result"] } : {}),
  };

  return {
    body,
    cacheControl: result.isComplete
      ? "public, s-maxage=600, stale-while-revalidate=1800"
      : "no-store",
  };
});
