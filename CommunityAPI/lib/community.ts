import { searchDaumArticles } from "./providers/daum.js";
import { searchNaverArticles } from "./providers/naver.js";
import type { ArticleSource, CommunityArticle } from "./types.js";

interface ArticleSearchParameters {
  title: string;
  author?: string;
  source: ArticleSource | "all";
  sort: "relevance" | "latest";
  page: number;
  kakaoAPIKey: string;
  naverClientID: string;
  naverClientSecret: string;
}

export async function searchCommunityArticles(
  parameters: ArticleSearchParameters,
): Promise<{ items: CommunityArticle[]; warnings: string[] }> {
  const query = buildBookQuery(parameters.title, parameters.author);
  const requestedSources: ArticleSource[] = parameters.source === "all"
    ? ["naver", "daum"]
    : [parameters.source];

  const results = await Promise.all(requestedSources.map(async (source) => {
    try {
      const items = source === "naver"
        ? await searchNaverArticles(
          query,
          parameters.sort,
          parameters.page,
          parameters.naverClientID,
          parameters.naverClientSecret,
        )
        : await searchDaumArticles(
          query,
          parameters.sort,
          parameters.page,
          parameters.kakaoAPIKey,
        );
      return { source, items };
    } catch {
      return { source, items: [] as CommunityArticle[], failed: true as const };
    }
  }));

  const warnings = results.flatMap((result) => result.failed ? [`${result.source}_unavailable`] : []);
  const items = mergeArticles(results.map((result) => result.items), parameters.sort);
  if (items.length === 0 && warnings.length === requestedSources.length) {
    throw new Error("all_article_sources_unavailable");
  }
  return { items, warnings };
}

export function buildBookQuery(title: string, author?: string): string {
  const normalizedTitle = title.replace(/[\[\](){}]/g, " ").replace(/\s+/g, " ").trim();
  const normalizedAuthor = normalizeAuthor(author);
  return [normalizedTitle, normalizedAuthor, "책"].filter(Boolean).join(" ");
}

function normalizeAuthor(author: string | undefined): string | undefined {
  const normalized = author?.replace(/\s+/g, " ").trim();
  if (!normalized) return undefined;

  const genericValues = new Set(["unknown", "미상", "작자 미상", "저자 미상"]);
  return genericValues.has(normalized.toLocaleLowerCase("ko-KR")) ? undefined : normalized;
}

export function mergeArticles(
  groups: CommunityArticle[][],
  sort: "relevance" | "latest",
): CommunityArticle[] {
  const unique = new Map<string, CommunityArticle>();
  const flattened = sort === "latest" ? groups.flat() : interleave(groups);

  for (const article of flattened) {
    const normalizedTitle = article.title.toLocaleLowerCase("ko-KR").replace(/\s+/g, "");
    const key = `${article.url}|${normalizedTitle}`;
    if (!unique.has(key)) unique.set(key, article);
  }

  const items = [...unique.values()];
  if (sort === "latest") {
    items.sort((left, right) => (right.publishedAt ?? "").localeCompare(left.publishedAt ?? ""));
  }
  return items.slice(0, 30);
}

function interleave<T>(groups: T[][]): T[] {
  const result: T[] = [];
  const maximumLength = Math.max(0, ...groups.map((group) => group.length));
  for (let index = 0; index < maximumLength; index += 1) {
    for (const group of groups) {
      const item = group[index];
      if (item !== undefined) result.push(item);
    }
  }
  return result;
}
