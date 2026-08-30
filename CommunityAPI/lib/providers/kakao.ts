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
  meta?: {
    is_end?: boolean;
    pageable_count?: number;
  };
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
  const outcomes = await Promise.allSettled(queries.map((queryKind) => searchKakaoPlaceKind(
    latitude,
    longitude,
    radius,
    queryKind,
    apiKey,
  )));
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
  timeoutMilliseconds = 7_000,
): Promise<BookMetadataCandidate[]> {
  const digits = query.replaceAll(/\D/g, "");
  const isISBN = digits.length === 10 || digits.length === 13;
  const primary = await requestKakaoBooks(
    isISBN ? digits : query,
    isISBN ? "isbn" : undefined,
    apiKey,
    timeoutMilliseconds,
  );
  if (primary.length > 0 || !isISBN) return primary;
  return await requestKakaoBooks(query, undefined, apiKey, timeoutMilliseconds);
}

async function requestKakaoBooks(
  query: string,
  target: "isbn" | undefined,
  apiKey: string,
  timeoutMilliseconds: number,
): Promise<BookMetadataCandidate[]> {
  const url = new URL("https://dapi.kakao.com/v3/search/book");
  url.searchParams.set("query", query);
  url.searchParams.set("sort", "accuracy");
  url.searchParams.set("page", "1");
  url.searchParams.set("size", "10");
  if (target) url.searchParams.set("target", target);

  const response = await fetchJSON<KakaoBookResponse>(url, {
    headers: { Authorization: `KakaoAK ${apiKey}` },
  }, timeoutMilliseconds);

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

async function searchKakaoPlaceKind(
  latitude: number,
  longitude: number,
  radius: number,
  kind: PlaceKind,
  apiKey: string,
): Promise<CommunityPlace[]> {
  const firstPage = await requestKakaoPlacePage(latitude, longitude, radius, kind, apiKey, 1);
  const places = normalizeKakaoPlaces(firstPage.documents ?? [], kind);
  if (places.length >= 15 || firstPage.meta?.is_end !== false) return places.slice(0, 15);

  // Kakao exposes at most 45 keyword results, so pages 2 and 3 cover every pageable candidate.
  const availableCount = Math.min(45, Math.max(15, firstPage.meta?.pageable_count ?? 45));
  const lastPage = Math.ceil(availableCount / 15);
  const additionalPages = Array.from({ length: Math.max(0, lastPage - 1) }, (_, index) => index + 2);
  const outcomes = await Promise.allSettled(additionalPages.map((page) => (
    requestKakaoPlacePage(latitude, longitude, radius, kind, apiKey, page)
  )));
  for (const outcome of outcomes) {
    if (outcome.status === "fulfilled") {
      places.push(...normalizeKakaoPlaces(outcome.value.documents ?? [], kind));
    }
  }
  return places.slice(0, 15);
}

async function requestKakaoPlacePage(
  latitude: number,
  longitude: number,
  radius: number,
  kind: PlaceKind,
  apiKey: string,
  page: number,
): Promise<KakaoPlaceResponse> {
  const url = new URL("https://dapi.kakao.com/v2/local/search/keyword.json");
  url.searchParams.set("query", kind === "bookstore" ? "서점" : "도서관");
  url.searchParams.set("x", longitude.toFixed(5));
  url.searchParams.set("y", latitude.toFixed(5));
  url.searchParams.set("radius", String(radius));
  url.searchParams.set("sort", "distance");
  url.searchParams.set("size", "15");
  url.searchParams.set("page", String(page));
  return await fetchJSON<KakaoPlaceResponse>(url, {
    headers: { Authorization: `KakaoAK ${apiKey}` },
  }, 2_500);
}

function normalizeDate(value: string | undefined): string {
  if (!value) return "";
  const match = /^\d{4}-\d{2}-\d{2}/.exec(value);
  return match?.[0] ?? cleanText(value);
}
