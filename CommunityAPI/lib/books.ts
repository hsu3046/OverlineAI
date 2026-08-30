import { searchAladinBooks } from "./providers/aladin.js";
import { searchKakaoBooks } from "./providers/kakao.js";
import type { BookMetadataCandidate } from "./types.js";

export interface BookMetadataSearchResult {
  items: BookMetadataCandidate[];
  message: string;
  isComplete: boolean;
}

export async function searchBookMetadata(
  query: string,
  aladinAPIKey: string,
  kakaoAPIKey: string,
): Promise<BookMetadataSearchResult> {
  const [aladinResult, kakaoResult] = await Promise.allSettled([
    searchAladinBooks(query, aladinAPIKey, 2_500),
    searchKakaoBooks(query, kakaoAPIKey, 2_500),
  ]);

  return resolveBookMetadataResults(aladinResult, kakaoResult);
}

export function resolveBookMetadataResults(
  aladinResult: PromiseSettledResult<BookMetadataCandidate[]>,
  kakaoResult: PromiseSettledResult<BookMetadataCandidate[]>,
): BookMetadataSearchResult {
  if (aladinResult.status === "fulfilled" && aladinResult.value.length > 0) {
    return {
      items: aladinResult.value,
      message: "Aladin 도서 검색 결과입니다.",
      isComplete: true,
    };
  }

  if (kakaoResult.status === "rejected") {
    throw kakaoResult.reason;
  }
  const kakaoItems = kakaoResult.value;
  return {
    items: kakaoItems,
    message: aladinResult.status === "rejected" && kakaoItems.length === 0
      ? "일부 검색 서비스를 불러오지 못했습니다."
      : kakaoItems.length > 0
        ? "Kakao 도서 검색 결과입니다."
        : "도서 검색 결과가 없습니다.",
    isComplete: aladinResult.status === "fulfilled",
  };
}
