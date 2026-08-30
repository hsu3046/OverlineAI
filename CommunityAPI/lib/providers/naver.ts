import { cleanText, fetchJSON, safeHTTPURL } from "../http.js";
import type { CommunityArticle } from "../types.js";

interface NaverBlogItem {
  title?: string;
  link?: string;
  description?: string;
  bloggername?: string;
  postdate?: string;
}

interface NaverBlogResponse {
  items?: NaverBlogItem[];
}

export async function searchNaverArticles(
  query: string,
  sort: "relevance" | "latest",
  page: number,
  clientID: string,
  clientSecret: string,
): Promise<CommunityArticle[]> {
  const url = new URL("https://naverapihub.apigw.ntruss.com/search/v1/blog");
  url.searchParams.set("query", query);
  url.searchParams.set("display", "20");
  url.searchParams.set("start", String(((page - 1) * 20) + 1));
  url.searchParams.set("sort", sort === "latest" ? "date" : "sim");
  url.searchParams.set("format", "json");

  const response = await fetchJSON<NaverBlogResponse>(url, {
    headers: {
      "X-NCP-APIGW-API-KEY-ID": clientID,
      "X-NCP-APIGW-API-KEY": clientSecret,
    },
  });

  return (response.items ?? []).flatMap((item) => {
    const title = cleanText(item.title);
    const url = safeHTTPURL(item.link);
    if (!title || !url) return [];

    const sourceName = cleanText(item.bloggername) || "NAVER 블로그";
    const publishedAt = normalizeNaverDate(item.postdate);
    return [{
      id: `naver-${url}`,
      title,
      snippet: cleanText(item.description),
      url,
      source: "naver" as const,
      sourceName,
      ...(publishedAt ? { publishedAt } : {}),
    }];
  });
}

function normalizeNaverDate(value: string | undefined): string | undefined {
  if (!value || !/^\d{8}$/.test(value)) return undefined;
  return `${value.slice(0, 4)}-${value.slice(4, 6)}-${value.slice(6, 8)}`;
}
