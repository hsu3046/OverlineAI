import { cleanText, fetchJSON, safeHTTPURL } from "../http.js";
import type { BookMetadataCandidate } from "../types.js";

interface RakutenBookItem {
  title?: string;
  author?: string;
  publisherName?: string;
  salesDate?: string;
  itemCaption?: string;
  itemUrl?: string;
  isbn?: string;
  largeImageUrl?: string;
  mediumImageUrl?: string;
  smallImageUrl?: string;
}

interface RakutenBookResponse {
  Items?: Array<RakutenBookItem | { Item: RakutenBookItem }>;
}

export function buildRakutenBookSearchURL(query: string, applicationID: string): URL {
  const url = new URL("https://openapi.rakuten.co.jp/services/api/BooksBook/Search/20170404");
  url.searchParams.set("applicationId", applicationID);
  url.searchParams.set("format", "json");
  url.searchParams.set("formatVersion", "2");
  url.searchParams.set("hits", "20");
  // Catalog lookup must include older and out-of-stock editions, not just products on sale.
  url.searchParams.set("outOfStockFlag", "1");

  const isbn = query.replace(/[\s-]/g, "").toUpperCase();
  if (/^(?:97[89]\d{10}|\d{9}[\dX])$/.test(isbn)) {
    url.searchParams.set("isbn", isbn);
  } else {
    url.searchParams.set("title", query);
  }
  return url;
}

export async function searchRakutenBooks(
  query: string,
  applicationID: string,
  accessKey: string,
  referer: string,
): Promise<BookMetadataCandidate[]> {
  const response = await fetchJSON<RakutenBookResponse>(buildRakutenBookSearchURL(query, applicationID), {
    headers: { accessKey, Referer: referer },
  }, 4_000);
  return normalizeRakutenBooks(response);
}

export function normalizeRakutenBooks(response: RakutenBookResponse): BookMetadataCandidate[] {
  return (response.Items ?? []).flatMap((entry) => {
    const item = "Item" in entry ? entry.Item : entry;
    const title = cleanText(item.title);
    const isbn = cleanText(item.isbn);
    const detailURL = safeHTTPURL(item.itemUrl);
    if (!title || !isbn) return [];
    return [{
      id: `rakuten-${isbn}`,
      title,
      author: cleanText(item.author),
      summary: cleanText(item.itemCaption),
      publisher: cleanText(item.publisherName),
      publishedDate: cleanText(item.salesDate),
      isbn,
      coverURLString: safeHTTPURL(item.largeImageUrl)
        ?? safeHTTPURL(item.mediumImageUrl)
        ?? safeHTTPURL(item.smallImageUrl)
        ?? "",
      source: "rakuten" as const,
      ...(detailURL ? { detailURL } : {}),
    }];
  });
}
