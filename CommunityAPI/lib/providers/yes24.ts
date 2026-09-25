import { cleanText, fetchJSON, safeHTTPURL } from "../http.js";
import type { BookMetadataCandidate } from "../types.js";

interface Yes24Book {
  itemId?: number;
  title?: string;
  author?: string;
  publisher?: string;
  publishDate?: string;
  isbn10?: string;
  isbn13?: string;
  cover?: string;
  link?: string;
  adultYn?: string;
  contentDetail?: { bookIntroduction?: string | null; bookSummary?: string | null };
}

interface Yes24Response {
  success?: boolean;
  errorCode?: string | null;
  data?: { items?: Yes24Book[] };
}

export async function searchYes24Books(query: string, apiKey: string): Promise<BookMetadataCandidate[]> {
  const url = new URL("https://apis.yes24.com/v1/goods/itemList");
  url.searchParams.set("query", query);
  url.searchParams.set("category", "BOOK");
  url.searchParams.set("page", "1");
  url.searchParams.set("pageSize", "10");
  const response = await fetchJSON<Yes24Response>(
    url,
    { headers: { "X-Api-Key": apiKey } },
    2_500,
  );
  if (!response.success) throw new Error(`yes24_${response.errorCode ?? "unknown"}`);
  return normalizeYes24Books(response);
}

export function normalizeYes24Books(response: Yes24Response): BookMetadataCandidate[] {
  return (response.data?.items ?? []).flatMap((item): BookMetadataCandidate[] => {
    const title = cleanText(item.title);
    if (!title || item.adultYn === "Y") return [];
    const isbn = cleanText(item.isbn13) || cleanText(item.isbn10);
    const detailURL = safeHTTPURL(item.link);
    return [{
      id: `yes24-${item.itemId ?? (isbn || title)}`,
      title,
      author: cleanText(item.author),
      summary: cleanText(item.contentDetail?.bookIntroduction ?? item.contentDetail?.bookSummary),
      publisher: cleanText(item.publisher),
      publishedDate: cleanText(item.publishDate),
      isbn,
      coverURLString: safeHTTPURL(item.cover) ?? "",
      source: "yes24",
      ...(detailURL ? { detailURL } : {}),
    }];
  });
}
