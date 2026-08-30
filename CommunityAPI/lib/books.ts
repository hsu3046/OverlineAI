import { searchAladinBooks } from "./providers/aladin.js";
import { searchKakaoBooks } from "./providers/kakao.js";
import type { BookMetadataCandidate } from "./types.js";

export async function searchBookMetadata(
  query: string,
  aladinAPIKey: string,
  kakaoAPIKey: string,
): Promise<{ items: BookMetadataCandidate[]; message: string }> {
  try {
    const aladinItems = await searchAladinBooks(query, aladinAPIKey);
    if (aladinItems.length > 0) {
      return { items: aladinItems, message: "Aladin 도서 검색 결과입니다." };
    }
  } catch {
    // Kakao provides the established fallback when Aladin is unavailable.
  }

  const kakaoItems = await searchKakaoBooks(query, kakaoAPIKey);
  return {
    items: kakaoItems,
    message: kakaoItems.length > 0
      ? "Kakao 도서 검색 결과입니다."
      : "도서 검색 결과가 없습니다.",
  };
}
