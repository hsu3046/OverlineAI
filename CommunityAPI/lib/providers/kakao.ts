import { cleanText, fetchJSON, integerValue, safeHTTPURL } from "../http.js";
import type { BookMetadataCandidate, CommunityPlace, PlaceKind } from "../types.js";

interface KakaoPlaceDocument {
  id?: string;
  place_name?: string;
  category_name?: string;
  phone?: string;
  address_name?: string;
  road_address_name?: string;
  place_url?: string;
  distance?: string;
}

interface KakaoPlaceResponse {
  documents?: KakaoPlaceDocument[];
}

interface KakaoBookDocument {
  title?: string;
  authors?: string[];
  contents?: string;
  publisher?: string;
  datetime?: string;
  isbn?: string;
  thumbnail?: string;
}

interface KakaoBookResponse {
  documents?: KakaoBookDocument[];
}

export async function searchKakaoPlaces(
  latitude: number,
  longitude: number,
  radius: number,
  kind: PlaceKind | "all",
  apiKey: string,
): Promise<CommunityPlace[]> {
  const queries: PlaceKind[] = kind === "all" ? ["bookstore", "library"] : [kind];
  const outcomes = await Promise.allSettled(queries.map(async (queryKind) => {
    const url = new URL("https://dapi.kakao.com/v2/local/search/keyword.json");
    url.searchParams.set("query", queryKind === "bookstore" ? "서점" : "도서관");
    url.searchParams.set("x", longitude.toFixed(5));
    url.searchParams.set("y", latitude.toFixed(5));
    url.searchParams.set("radius", String(radius));
    url.searchParams.set("sort", "distance");
    url.searchParams.set("size", "15");

    const response = await fetchJSON<KakaoPlaceResponse>(url, {
      headers: { Authorization: `KakaoAK ${apiKey}` },
    });
    return normalizeKakaoPlaces(response.documents ?? [], queryKind);
  }));
  const responses = outcomes.flatMap((outcome) => outcome.status === "fulfilled" ? [outcome.value] : []);
  if (responses.length === 0) {
    const failure = outcomes.find((outcome) => outcome.status === "rejected");
    throw failure?.reason ?? new Error("kakao_places_unavailable");
  }

  const uniquePlaces = new Map<string, CommunityPlace>();
  for (const place of responses.flat()) {
    const existing = uniquePlaces.get(place.id);
    if (!existing || place.distanceMeters < existing.distanceMeters) {
      uniquePlaces.set(place.id, place);
    }
  }

  return [...uniquePlaces.values()]
    .sort((left, right) => left.distanceMeters - right.distanceMeters)
    .slice(0, 30);
}

export function normalizeKakaoPlaces(
  documents: KakaoPlaceDocument[],
  fallbackKind: PlaceKind,
): CommunityPlace[] {
  return documents.flatMap((document) => {
    const name = cleanText(document.place_name);
    const address = cleanText(document.road_address_name) || cleanText(document.address_name);
    const distanceMeters = integerValue(document.distance);
    if (!name || !address || distanceMeters === undefined) return [];

    const category = cleanText(document.category_name);
    if (!matchesPlaceCategory(category, fallbackKind)) return [];

    const identifier = cleanText(document.id) || `${name}-${address}`;
    const phone = cleanText(document.phone);
    const detailURL = safeHTTPURL(document.place_url);

    return [{
      id: `kakao-${identifier}`,
      name,
      kind: fallbackKind,
      category,
      address,
      distanceMeters,
      source: "kakao" as const,
      ...(phone ? { phone } : {}),
      ...(detailURL ? { detailURL } : {}),
    }];
  });
}

export function matchesPlaceCategory(category: string, kind: PlaceKind): boolean {
  const parts = category.split(">").map((part) => part.trim()).filter(Boolean);
  if (kind === "bookstore") {
    return parts.some((part) => part === "서점" || part.endsWith("서점"));
  }
  return parts.some((part) => part === "도서관" || part.endsWith("도서관"));
}

export async function searchKakaoBooks(
  query: string,
  apiKey: string,
): Promise<BookMetadataCandidate[]> {
  const digits = query.replaceAll(/\D/g, "");
  const isISBN = digits.length === 10 || digits.length === 13;
  const primary = await requestKakaoBooks(isISBN ? digits : query, isISBN ? "isbn" : undefined, apiKey);
  if (primary.length > 0 || !isISBN) return primary;
  return await requestKakaoBooks(query, undefined, apiKey);
}

async function requestKakaoBooks(
  query: string,
  target: "isbn" | undefined,
  apiKey: string,
): Promise<BookMetadataCandidate[]> {
  const url = new URL("https://dapi.kakao.com/v3/search/book");
  url.searchParams.set("query", query);
  url.searchParams.set("sort", "accuracy");
  url.searchParams.set("page", "1");
  url.searchParams.set("size", "10");
  if (target) url.searchParams.set("target", target);

  const response = await fetchJSON<KakaoBookResponse>(url, {
    headers: { Authorization: `KakaoAK ${apiKey}` },
  });

  return (response.documents ?? []).flatMap((document) => {
    const title = cleanText(document.title);
    if (!title) return [];
    const isbn = cleanText(document.isbn);

    return [{
      id: `kakao-${isbn}-${title}`,
      title,
      author: (document.authors ?? []).map(cleanText).filter(Boolean).join(", "),
      summary: cleanText(document.contents),
      publisher: cleanText(document.publisher),
      publishedDate: normalizeDate(document.datetime),
      isbn,
      coverURLString: safeHTTPURL(document.thumbnail) ?? "",
      source: "kakao" as const,
    }];
  });
}

function normalizeDate(value: string | undefined): string {
  if (!value) return "";
  const match = /^\d{4}-\d{2}-\d{2}/.exec(value);
  return match?.[0] ?? cleanText(value);
}
