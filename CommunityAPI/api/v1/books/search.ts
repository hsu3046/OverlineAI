import { createGETHandler, requiredEnvironment, requiredQuery } from "../../../lib/http.js";
import { searchBookMetadata } from "../../../lib/books.js";

export default createGETHandler(async (url) => {
  const query = requiredQuery(url, "q", 160);
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
    cacheControl: result.isComplete
      ? "public, s-maxage=86400, stale-while-revalidate=604800"
      : "no-store",
  };
});
