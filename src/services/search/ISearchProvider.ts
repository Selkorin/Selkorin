export interface SearchResult {
  title: string;
  url: string;
  snippet: string;
}

export interface ISearchProvider {
  readonly name: string;
  /** True when the required API credentials are available. */
  isConfigured(): Promise<boolean>;
  /** Run a web search and return normalized results. Throws on API errors. */
  search(query: string, limit: number): Promise<SearchResult[]>;
}
