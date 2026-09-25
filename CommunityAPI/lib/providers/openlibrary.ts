import { cleanText, fetchJSON } from "../http.js";
import type { BookMetadataCandidate } from "../types.js";

interface OpenLibraryResponse {
  docs?: Array<{
    key?: string;
    title?: string;
    author_name?: string[];
    publisher?: string[];
    first_publish_year?: number;
    isbn?: string[];
    cover_i?: number;
  }>;
}

export async function searchOpenLibraryBooks(query: string, language: "ja" | "en"): Promise<BookMetadataCandidate[]> {
  const url = new URL("https://openlibrary.org/search.json");
  url.searchParams.set("q", query);
  url.searchParams.set("lang", language);
  url.searchParams.set("fields", "key,title,author_name,publisher,first_publish_year,isbn,cover_i");
  url.searchParams.set("limit", "20");
  const response = await fetchJSON<OpenLibraryResponse>(url, {
    headers: { "User-Agent": "BZOGAK/1.0 (https://bzogak.aib.vote)" },
  }, 4_000);
  return rankOpenLibraryBooks(normalizeOpenLibraryBooks(response, query), query);
}

export function rankOpenLibraryBooks(books: BookMetadataCandidate[], query: string): BookMetadataCandidate[] {
  const normalizedQuery = normalizeTitle(query);
  const queryISBN = query.replace(/\D/g, "");
  return [...books].sort((left, right) => {
    const rank = (book: BookMetadataCandidate) => {
      if ((queryISBN.length === 10 || queryISBN.length === 13) && book.isbn === queryISBN) return 0;
      if (normalizeTitle(book.title) === normalizedQuery) return 1;
      if (normalizeTitle(book.title).startsWith(normalizedQuery)) return 2;
      return 3;
    };
    return rank(left) - rank(right);
  });
}

function normalizeTitle(value: string): string {
  return value.normalize("NFKC").toLocaleLowerCase().replace(/[\p{P}\p{S}\s]/gu, "");
}

export function normalizeOpenLibraryBooks(response: OpenLibraryResponse, query = ""): BookMetadataCandidate[] {
  return (response.docs ?? []).flatMap((doc) => {
    const title = cleanText(doc.title);
    if (!doc.key || !title) return [];
    const queryISBN = query.replace(/\D/g, "");
    const isbn = doc.isbn?.find((value) => value.replace(/\D/g, "") === queryISBN && queryISBN.length >= 10)
      ?? doc.isbn?.find((value) => /^97[89]\d{10}$/.test(value)) ?? doc.isbn?.[0] ?? "";
    return [{
      id: `openlibrary-${doc.key}`,
      title,
      author: (doc.author_name ?? []).map(cleanText).filter(Boolean).join(", "),
      summary: "",
      publisher: cleanText(doc.publisher?.[0]),
      publishedDate: doc.first_publish_year?.toString() ?? "",
      isbn,
      coverURLString: doc.cover_i ? `https://covers.openlibrary.org/b/id/${doc.cover_i}-M.jpg` : "",
      source: "openLibrary" as const,
    }];
  });
}
