import { searchAladinBooks } from "./providers/aladin.js";
import { searchKakaoBooks } from "./providers/kakao.js";
import type { BookMetadataCandidate } from "./types.js";

export async function searchBookMetadata(
  query: string,
  aladinAPIKey: string,
  kakaoAPIKey: string,
): Promise<{ items: BookMetadataCandidate[]; message: string }> {
  const [aladinResult, kakaoResult] = await Promise.allSettled([
    searchAladinBooks(query, aladinAPIKey, 2_500),
    searchKakaoBooks(query, kakaoAPIKey, 2_500),
  ]);

  if (aladinResult.status === "fulfilled" && aladinResult.value.length > 0) {
    return { items: aladinResult.value, message: "Aladin 도서 검색 결과입니다." };
  }

  if (kakaoResult.status === "rejected") {
    throw kakaoResult.reason;
  }
  const kakaoItems = kakaoResult.value;
  return {
    items: kakaoItems,
    message: kakaoItems.length > 0
      ? "Kakao 도서 검색 결과입니다."
      : "도서 검색 결과가 없습니다.",
  };
}
