import type { CommunityRankingItem, RankingSource } from "./types.js";

export interface RankingSnapshot {
  items: CommunityRankingItem[];
  fetchedAt: string;
}

function isItem(value: unknown, source: RankingSource): value is CommunityRankingItem {
  if (typeof value !== "object" || value === null) return false;
  const item = value as Record<string, unknown>;
  return typeof item.id === "string"
    && typeof item.title === "string"
    && typeof item.author === "string"
    && item.source === source
    && Number.isSafeInteger(item.rank)
    && Number(item.rank) > 0;
}

/**
 * Read the private KnowAI snapshot. A 404 means the manual SQL or first sync is
 * not ready yet; other errors must not fan out into per-user provider requests.
 */
export async function readRankingSnapshot(
  source: "yes24" | "data4library" | "rakuten",
  category: string,
): Promise<RankingSnapshot | undefined> {
  const endpoint = process.env.KNOWAI_RANKING_CACHE_URL;
  const secret = process.env.BZOGAK_BOOK_BRIDGE_SECRET;
  if (!endpoint || !secret) return undefined;

  const url = new URL(endpoint);
  if (url.protocol !== "https:") throw new Error("ranking_cache_requires_https");
  url.searchParams.set("source", source);
  url.searchParams.set("category", category);

  const response = await fetch(url, {
    headers: { "x-bzogak-bridge-secret": secret },
    signal: AbortSignal.timeout(5_000),
    cache: "no-store",
  });
  if (response.status === 404) return undefined;
  if (!response.ok) throw new Error(`ranking_cache_http_${response.status}`);
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) throw new Error("invalid_ranking_snapshot");
  const data = payload as Record<string, unknown>;
  const fetchedAt = typeof data.fetchedAt === "string" ? Date.parse(data.fetchedAt) : Number.NaN;
  if (!Array.isArray(data.items)
    || data.items.length > 100
    || !data.items.every((item) => isItem(item, source))
    || !Number.isFinite(fetchedAt)
    || fetchedAt > Date.now() + 300_000
    || Date.now() - fetchedAt > 7 * 86_400_000
  ) {
    throw new Error("invalid_or_expired_ranking_snapshot");
  }
  return { items: data.items, fetchedAt: data.fetchedAt as string };
}
