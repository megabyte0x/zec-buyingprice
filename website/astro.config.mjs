import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';
import { unified } from '@astrojs/markdown-remark';

function focusableScrollRegions() {
  return (tree) => {
    const visit = (node) => {
      if (node.type === 'element' && ['table', 'pre'].includes(node.tagName)) {
        node.properties = { ...node.properties, tabIndex: 0 };
      }
      node.children?.forEach(visit);
    };
    visit(tree);
  };
}

export default defineConfig({
  site: 'https://zecbuyingprice.megabyte.sh',
  trailingSlash: 'always',
  markdown: { processor: unified({ rehypePlugins: [focusableScrollRegions] }) },
  integrations: [
    react(),
    sitemap({ filter: (page) => !page.endsWith('/404/') && !page.endsWith('/404.html') }),
  ],
  vite: { plugins: [tailwindcss()] },
});
