import { cleanText, fetchJSON, safeHTTPURL } from "../http.js";
import type { BookMetadataCandidate, CommunityPlace, PlaceKind } from "../types.js";

interface GoogleVolumeResponse {
  items?: Array<{
    id?: string;
    volumeInfo?: {
      title?: string;
      authors?: string[];
      description?: string;
      publisher?: string;
      publishedDate?: string;
      industryIdentifiers?: Array<{ type?: string; identifier?: string }>;
      imageLinks?: { thumbnail?: string };
    };
  }>;
}

export async function searchGoogleBooks(query: string, language: "ja" | "en", apiKey?: string): Promise<BookMetadataCandidate[]> {
  const url = new URL("https://www.googleapis.com/books/v1/volumes");
  url.searchParams.set("q", query);
  url.searchParams.set("langRestrict", language);
  url.searchParams.set("printType", "books");
  url.searchParams.set("maxResults", "20");
  if (apiKey) url.searchParams.set("key", apiKey);
  const response = await fetchJSON<GoogleVolumeResponse>(url, {}, 4_000);
  return normalizeGoogleBooks(response);
}

export function normalizeGoogleBooks(response: GoogleVolumeResponse): BookMetadataCandidate[] {
  return (response.items ?? []).flatMap((item) => {
    const volume = item.volumeInfo;
    const title = cleanText(volume?.title);
    if (!item.id || !title) return [];
    const identifiers = volume?.industryIdentifiers ?? [];
    const isbn = identifiers.find((identifier) => identifier.type === "ISBN_13")?.identifier
      ?? identifiers.find((identifier) => identifier.type === "ISBN_10")?.identifier ?? "";
    return [{
      id: `google-${item.id}`,
      title,
      author: (volume?.authors ?? []).map(cleanText).filter(Boolean).join(", "),
      summary: cleanText(volume?.description),
      publisher: cleanText(volume?.publisher),
      publishedDate: cleanText(volume?.publishedDate),
      isbn,
      coverURLString: safeHTTPURL(volume?.imageLinks?.thumbnail) ?? "",
      source: "google" as const,
    }];
  });
}

interface GooglePlacesResponse {
  places?: Array<{
    id?: string;
    displayName?: { text?: string };
    primaryType?: string;
    types?: string[];
    primaryTypeDisplayName?: { text?: string };
    formattedAddress?: string;
    location?: { latitude?: number; longitude?: number };
    googleMapsUri?: string;
  }>;
}

export async function searchGooglePlaces(
  latitude: number,
  longitude: number,
  radius: number,
  kind: PlaceKind | "all",
  language: "ja" | "en",
  region: string,
  apiKey: string,
): Promise<CommunityPlace[]> {
  const types = kind === "all" ? ["book_store", "library"] : [kind === "bookstore" ? "book_store" : "library"];
  const response = await fetchJSON<GooglePlacesResponse>(new URL("https://places.googleapis.com/v1/places:searchNearby"), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "places.id,places.displayName,places.primaryType,places.types,places.primaryTypeDisplayName,places.formattedAddress,places.location,places.googleMapsUri",
    },
    body: JSON.stringify({
      includedTypes: types,
      maxResultCount: 20,
      rankPreference: "DISTANCE",
      languageCode: language,
      regionCode: region,
      locationRestriction: { circle: { center: { latitude, longitude }, radius } },
    }),
  }, 4_000);
  return normalizeGooglePlaces(response, latitude, longitude, kind);
}

export function normalizeGooglePlaces(
  response: GooglePlacesResponse,
  latitude: number,
  longitude: number,
  requestedKind: PlaceKind | "all",
): CommunityPlace[] {
  return (response.places ?? []).flatMap((place) => {
    const name = cleanText(place.displayName?.text);
    const address = cleanText(place.formattedAddress);
    const location = place.location;
    if (!place.id || !name || !address || location?.latitude === undefined || location.longitude === undefined) return [];
    const kind: PlaceKind = requestedKind === "all"
      ? place.primaryType === "library" || place.types?.includes("library") === true
        ? "library" : "bookstore"
      : requestedKind;
    const mapsURL = new URL("https://www.google.com/maps/search/");
    mapsURL.searchParams.set("api", "1");
    mapsURL.searchParams.set("query", name);
    mapsURL.searchParams.set("query_place_id", place.id);
    const detailURL = safeHTTPURL(place.googleMapsUri) ?? mapsURL.toString();
    return [{
      id: `google-${place.id}`,
      name,
      kind,
      category: cleanText(place.primaryTypeDisplayName?.text),
      address,
      distanceMeters: Math.round(distanceInMeters(latitude, longitude, location.latitude, location.longitude)),
      source: "google" as const,
      detailURL,
    }];
  });
}

function distanceInMeters(latitude1: number, longitude1: number, latitude2: number, longitude2: number): number {
  const radians = Math.PI / 180;
  const latitudeDelta = (latitude2 - latitude1) * radians;
  const longitudeDelta = (longitude2 - longitude1) * radians;
  const arc = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(latitude1 * radians) * Math.cos(latitude2 * radians) * Math.sin(longitudeDelta / 2) ** 2;
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(arc), Math.sqrt(1 - arc));
}
