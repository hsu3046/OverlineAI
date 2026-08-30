import { cleanText, fetchJSON, integerValue, safeHTTPURL } from "../http.js";
import type { CommunityRankingItem } from "../types.js";

interface Data4LibraryDocument {
  ranking?: string | number;
  bookname?: string;
  authors?: string;
  publisher?: string;
  publication_year?: string;
  isbn13?: string;
  bookImageURL?: string;
  bookDtlUrl?: string;
  loan_count?: string | number;
}

interface WrappedDocument {
  doc?: Data4LibraryDocument;
}

interface Data4LibraryResponse {
  response?: {
    docs?: WrappedDocument[];
  };
}

export async function fetchPopularLoans(
  page: number,
  apiKey: string,
  now = new Date(),
): Promise<CommunityRankingItem[]> {
  const endDate = new Date(now);
  endDate.setUTCDate(endDate.getUTCDate() - 1);
  const startDate = new Date(endDate);
  startDate.setUTCDate(startDate.getUTCDate() - 29);

  const url = new URL("https://data4library.kr/api/loanItemSrch");
  url.searchParams.set("authKey", apiKey);
  url.searchParams.set("startDt", formatDate(startDate));
  url.searchParams.set("endDt", formatDate(endDate));
  url.searchParams.set("pageNo", String(page));
  url.searchParams.set("pageSize", "20");
  url.searchParams.set("format", "json");

  const response = await fetchJSON<Data4LibraryResponse>(url);
  return normalizePopularLoans(response.response?.docs ?? [], page);
}

export function normalizePopularLoans(
  documents: WrappedDocument[],
  page: number,
): CommunityRankingItem[] {
  return documents.flatMap((wrapper, index) => {
    const document = wrapper.doc;
    if (!document) return [];
    const title = cleanText(document.bookname);
    if (!title) return [];

    const isbn13 = cleanText(document.isbn13);
    const coverURL = safeHTTPURL(document.bookImageURL);
    const detailURL = safeHTTPURL(document.bookDtlUrl);
    const rank = integerValue(document.ranking) ?? (((page - 1) * 20) + index + 1);
    const loanCount = integerValue(document.loan_count);

    return [{
      id: `data4library-${isbn13 || title}`,
      rank,
      title,
      author: cleanText(document.authors),
      source: "data4library" as const,
      ...(cleanText(document.publisher) ? { publisher: cleanText(document.publisher) } : {}),
      ...(cleanText(document.publication_year) ? { publishedDate: cleanText(document.publication_year) } : {}),
      ...(isbn13 ? { isbn13 } : {}),
      ...(coverURL ? { coverURL } : {}),
      ...(detailURL ? { detailURL } : {}),
      ...(loanCount !== undefined ? { loanCount } : {}),
    }];
  });
}

function formatDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}
