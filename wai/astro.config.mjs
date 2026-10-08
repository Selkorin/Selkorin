import { defineConfig } from 'astro/config';

export default defineConfig({
  // Canonical domain: used for canonical links, Open Graph and the sitemap.
  site: 'https://wai-marketing.ru',
  // Keep URLs identical to the original static site: /services/web.html, /insights/index.html, ...
  build: { format: 'preserve' },
  trailingSlash: 'ignore',
});
