import { cleanText, fetchJSON, safeHTTPURL } from "../http.js";
import type { CommunityArticle } from "../types.js";

interface DaumBlogDocument {
  title?: string;
  contents?: string;
  url?: string;
  blogname?: string;
  thumbnail?: string;
  datetime?: string;
}

interface DaumBlogResponse {
  documents?: DaumBlogDocument[];
}

export async function searchDaumArticles(
  query: string,
  sort: "relevance" | "latest",
  page: number,
  apiKey: string,
): Promise<CommunityArticle[]> {
  const url = new URL("https://dapi.kakao.com/v2/search/blog");
  url.searchParams.set("query", query);
  url.searchParams.set("sort", sort === "latest" ? "recency" : "accuracy");
  url.searchParams.set("page", String(page));
  url.searchParams.set("size", "20");

  const response = await fetchJSON<DaumBlogResponse>(url, {
    headers: { Authorization: `KakaoAK ${apiKey}` },
  });

  return (response.documents ?? []).flatMap((document) => {
    const title = cleanText(document.title);
    const url = safeHTTPURL(document.url);
    if (!title || !url) return [];

    const publishedAt = normalizeDaumDate(document.datetime);
    const thumbnailURL = safeHTTPURL(document.thumbnail);
    return [{
      id: `daum-${url}`,
      title,
      snippet: cleanText(document.contents),
      url,
      source: "daum" as const,
      sourceName: cleanText(document.blogname) || "Daum 블로그",
      ...(publishedAt ? { publishedAt } : {}),
      ...(thumbnailURL ? { thumbnailURL } : {}),
    }];
  });
}

function normalizeDaumDate(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const match = /^\d{4}-\d{2}-\d{2}/.exec(value);
  return match?.[0];
}
