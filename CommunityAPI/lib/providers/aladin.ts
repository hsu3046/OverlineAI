import { cleanText, fetchJSON, integerValue, safeHTTPURL } from "../http.js";
import type { BookMetadataCandidate, CommunityRankingItem } from "../types.js";

interface AladinItem {
  itemId?: number;
  title?: string;
  author?: string;
  description?: string;
  publisher?: string;
  pubDate?: string;
  isbn?: string;
  isbn13?: string;
  cover?: string;
  link?: string;
}

interface AladinResponse {
  item?: AladinItem[];
  errorCode?: string | number;
  errorMessage?: string;
}

export async function searchAladinBooks(
  query: string,
  apiKey: string,
): Promise<BookMetadataCandidate[]> {
  const digits = query.replaceAll(/\D/g, "");
  if (digits.length === 10 || digits.length === 13) {
    const lookupItems = await requestAladin("ItemLookUp.aspx", {
      ItemId: digits,
      ItemIdType: digits.length === 13 ? "ISBN13" : "ISBN",
    }, apiKey);
    if (lookupItems.length > 0) return lookupItems.map(normalizeBookCandidate);
  }

  const titleItems = await requestAladin("ItemSearch.aspx", {
    Query: query,
    QueryType: "Title",
    MaxResults: "10",
    Start: "1",
    SearchTarget: "Book",
    Sort: "Accuracy",
  }, apiKey);
  if (titleItems.length > 0 || digits.length === 10 || digits.length === 13) {
    return titleItems.map(normalizeBookCandidate).filter((item) => item.title.length > 0);
  }

  const keywordItems = await requestAladin("ItemSearch.aspx", {
    Query: query,
    QueryType: "Keyword",
    MaxResults: "10",
    Start: "1",
    SearchTarget: "Book",
    Sort: "Accuracy",
  }, apiKey);
  return keywordItems.map(normalizeBookCandidate).filter((item) => item.title.length > 0);
}

export async function fetchAladinBestsellers(
  page: number,
  apiKey: string,
): Promise<CommunityRankingItem[]> {
  const items = await requestAladin("ItemList.aspx", {
    QueryType: "Bestseller",
    MaxResults: "20",
    Start: String(page),
    SearchTarget: "Book",
  }, apiKey);

  return items.flatMap((item, index) => {
    const title = cleanText(item.title);
    if (!title) return [];
    const isbn13 = cleanText(item.isbn13);
    const detailURL = safeHTTPURL(item.link);
    const coverURL = safeHTTPURL(item.cover);
    const itemID = integerValue(item.itemId);

    return [{
      id: `aladin-${itemID ?? (isbn13 || title)}`,
      rank: ((page - 1) * 20) + index + 1,
      title,
      author: cleanText(item.author),
      source: "aladin" as const,
      ...(cleanText(item.publisher) ? { publisher: cleanText(item.publisher) } : {}),
      ...(cleanText(item.pubDate) ? { publishedDate: cleanText(item.pubDate) } : {}),
      ...(isbn13 ? { isbn13 } : {}),
      ...(coverURL ? { coverURL } : {}),
      ...(detailURL ? { detailURL } : {}),
    }];
  });
}

async function requestAladin(
  endpoint: string,
  parameters: Readonly<Record<string, string>>,
  apiKey: string,
): Promise<AladinItem[]> {
  const url = new URL(`https://www.aladin.co.kr/ttb/api/${endpoint}`);
  url.searchParams.set("TTBKey", apiKey);
  url.searchParams.set("Cover", "Big");
  url.searchParams.set("Output", "JS");
  url.searchParams.set("Version", "20131101");
  for (const [name, value] of Object.entries(parameters)) {
    url.searchParams.set(name, value);
  }

  const response = await fetchJSON<AladinResponse>(url);
  if (response.errorCode !== undefined) {
    throw new Error(`aladin_${String(response.errorCode)}_${cleanText(response.errorMessage).slice(0, 80)}`);
  }
  return response.item ?? [];
}

function normalizeBookCandidate(item: AladinItem): BookMetadataCandidate {
  const isbnValues = [cleanText(item.isbn), cleanText(item.isbn13)].filter(Boolean);
  const isbn = [...new Set(isbnValues)].join(" ");
  const title = cleanText(item.title);

  return {
    id: `aladin-${isbn}-${title}`,
    title,
    author: cleanText(item.author),
    summary: cleanText(item.description),
    publisher: cleanText(item.publisher),
    publishedDate: cleanText(item.pubDate),
    isbn,
    coverURLString: safeHTTPURL(item.cover) ?? "",
    source: "aladin",
  };
}
