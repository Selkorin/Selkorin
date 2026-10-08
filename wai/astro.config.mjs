import { defineConfig } from 'astro/config';

export default defineConfig({
  // Keep URLs identical to the original static site: /services/web.html, /insights/index.html, ...
  build: { format: 'preserve' },
  trailingSlash: 'ignore',
});
