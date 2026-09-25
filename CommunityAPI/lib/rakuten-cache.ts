import type { BookMetadataCandidate } from "./types.js";

/** A pending VM job returns no result yet; caller uses the existing search fallback. */
export async function searchCachedRakutenBooks(query: string): Promise<BookMetadataCandidate[] | undefined> {
  const endpoint = process.env.KNOWAI_RAKUTEN_SEARCH_URL;
  const secret = process.env.BZOGAK_BOOK_BRIDGE_SECRET;
  if (!endpoint || !secret) return undefined;
  const url = new URL(endpoint);
  if (url.protocol !== "https:") throw new Error("rakuten_cache_requires_https");
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-bzogak-bridge-secret": secret,
    },
    body: JSON.stringify({ query }),
    signal: AbortSignal.timeout(4_000),
    cache: "no-store",
  });
  if (response.status === 202) return undefined;
  if (!response.ok) throw new Error(`rakuten_cache_http_${response.status}`);
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) throw new Error("invalid_rakuten_cache");
  const items = (payload as Record<string, unknown>).items;
  if (!Array.isArray(items) || items.length > 20 || !items.every((item) => {
    if (typeof item !== "object" || item === null) return false;
    const book = item as Record<string, unknown>;
    return book.source === "rakuten"
      && typeof book.id === "string"
      && typeof book.title === "string"
      && typeof book.author === "string"
      && typeof book.isbn === "string";
  })) {
    throw new Error("invalid_rakuten_cache");
  }
  return items as BookMetadataCandidate[];
}
