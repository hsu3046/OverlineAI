import { createPOSTHandler, enumBody, integerBody, numberBody, optionalBodyString, requiredEnvironment } from "../../lib/http.js";
import { searchKakaoPlaces } from "../../lib/providers/kakao.js";
import { searchGooglePlaces } from "../../lib/providers/google.js";
import type { ListResponse, PlaceKind, CommunityPlace } from "../../lib/types.js";

export default createPOSTHandler(async (requestBody) => {
  const latitude = numberBody(requestBody, "latitude", { minimum: -90, maximum: 90 });
  const longitude = numberBody(requestBody, "longitude", { minimum: -180, maximum: 180 });
  const radius = requestBody.radius === undefined
    ? 5_000
    : integerBody(requestBody, "radius", { minimum: 500, maximum: 20_000 });
  const kind = enumBody(requestBody, "kind", ["all", "bookstore", "library"] as const, "all");
  const language = enumBody(requestBody, "language", ["ko", "ja", "en"] as const, "ko");
  const requestedRegion = optionalBodyString(requestBody, "region", 2)?.toUpperCase();
  const region = requestedRegion && /^[A-Z]{2}$/.test(requestedRegion) ? requestedRegion : language === "ja" ? "JP" : "US";
  if (language !== "ko") {
    const items = await searchGooglePlaces(latitude, longitude, radius, kind, language, region, requiredEnvironment("GOOGLE_PLACES_API_KEY"));
    return {
      body: { items, fetchedAt: new Date().toISOString() } satisfies ListResponse<CommunityPlace>,
      cacheControl: "no-store",
    };
  }
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
