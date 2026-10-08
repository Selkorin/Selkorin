// Sitemap built from the page routes. Pages marked noindex are left out.
import type { APIRoute } from 'astro';

const SITE = 'https://waimarketing.ai';
const EXCLUDE = ['WAI Website'];

export const prerender = true;

export const GET: APIRoute = () => {
  const pages = import.meta.glob('./**/*.astro', { eager: true });
  const urls = Object.keys(pages)
    .map(p => p.replace(/^\.\//, '').replace(/\.astro$/, ''))
    .filter(p => !EXCLUDE.includes(p))
    .map(p => (p === 'index' ? '/' : `/${p}.html`))
    .sort((a, b) => (a === '/' ? -1 : b === '/' ? 1 : a.localeCompare(b)));

  const body = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map(u => `  <url><loc>${SITE}${u}</loc></url>`).join('\n')}
</urlset>
`;
  return new Response(body, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
