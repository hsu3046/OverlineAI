import { createPOSTHandler, requiredBodyString, requiredEnvironment } from "../../../lib/http.js";
import { searchBookMetadata } from "../../../lib/books.js";

export default createPOSTHandler(async (requestBody) => {
  const query = requiredBodyString(requestBody, "query", 160);
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
