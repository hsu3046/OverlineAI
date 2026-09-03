import { createPOSTHandler, enumBody, integerBody, numberBody, requiredEnvironment } from "../../lib/http.js";
import { searchKakaoPlaces } from "../../lib/providers/kakao.js";
import type { ListResponse, PlaceKind, CommunityPlace } from "../../lib/types.js";

export default createPOSTHandler(async (requestBody) => {
  const latitude = numberBody(requestBody, "latitude", { minimum: -90, maximum: 90 });
  const longitude = numberBody(requestBody, "longitude", { minimum: -180, maximum: 180 });
  const radius = requestBody.radius === undefined
    ? 5_000
    : integerBody(requestBody, "radius", { minimum: 500, maximum: 20_000 });
  const kind = enumBody(requestBody, "kind", ["all", "bookstore", "library"] as const, "all");
  const apiKey = requiredEnvironment("KAKAO_REST_API_KEY");
  const result = await searchKakaoPlaces(latitude, longitude, radius, kind as PlaceKind | "all", apiKey);
  const body: ListResponse<CommunityPlace> = {
    items: result.items,
    fetchedAt: new Date().toISOString(),
    ...(!result.isComplete ? { warnings: ["kakao_partial_result"] } : {}),
  };

  return {
    body,
    cacheControl: "no-store",
  };
});
