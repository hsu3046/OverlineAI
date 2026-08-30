export type PlaceKind = "bookstore" | "library";
export type ArticleSource = "naver" | "daum";
export type RankingSource = "aladin" | "data4library";

export interface CommunityPlace {
  id: string;
  name: string;
  kind: PlaceKind;
  category: string;
  address: string;
  distanceMeters: number;
  source: "kakao";
  phone?: string;
  detailURL?: string;
}

export interface CommunityArticle {
  id: string;
  title: string;
  snippet: string;
  url: string;
  source: ArticleSource;
  sourceName: string;
  publishedAt?: string;
  thumbnailURL?: string;
}

export interface CommunityRankingItem {
  id: string;
  rank: number;
  title: string;
  author: string;
  source: RankingSource;
  publisher?: string;
  publishedDate?: string;
  isbn13?: string;
  coverURL?: string;
  detailURL?: string;
  loanCount?: number;
}

export interface BookMetadataCandidate {
  id: string;
  title: string;
  author: string;
  summary: string;
  publisher: string;
  publishedDate: string;
  isbn: string;
  coverURLString: string;
  source: "kakao" | "aladin";
}

export interface ListResponse<T> {
  items: T[];
  fetchedAt: string;
  warnings?: string[];
}
