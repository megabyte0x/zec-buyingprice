import { readdir, readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import assert from 'node:assert/strict';
const root = new URL('../dist/', import.meta.url).pathname;
async function files(dir) {const out=[];for(const name of await readdir(dir)){const path=join(dir,name);if((await stat(path)).isDirectory())out.push(...await files(path));else out.push(path);}return out;}
const all = await files(root);
const htmlFiles = all.filter(p=>p.endsWith('.html'));
const titles = new Set();
const descriptions = new Set();
let links=0,schemas=0;
for(const path of htmlFiles){
  const html=await readFile(path,'utf8');
  const title=html.match(/<title>(.*?)<\/title>/s)?.[1];
  const description=html.match(/<meta name="description" content="([^"]+)"/)?.[1];
  assert(title && !titles.has(title),`Missing or repeated title: ${path}`);titles.add(title);
  assert(description && !descriptions.has(description),`Missing or repeated description: ${path}`);descriptions.add(description);
  assert.equal((html.match(/<h1[ >]/g)||[]).length,1,`Expected one h1: ${path}`);
  assert(html.includes('rel="canonical" href="https://zecbuyingprice.megabyte.sh/'),`Canonical: ${path}`);
  assert(html.includes('<html lang="en"'),`Language: ${path}`);
  for(const match of html.matchAll(/<script type="application\/ld\+json"[^>]*>(.*?)<\/script>/gs)){JSON.parse(match[1]);schemas++;}
  for(const match of html.matchAll(/(?:href|src)="(\/[^"#]*)/g)){
    const url=match[1].split('?')[0];if(url==='/download/' || url==='/download') continue;
    const target=join(root,url.endsWith('/')?url+'index.html':url);
    assert(all.includes(target),`Broken local link ${url} in ${path}`);links++;
  }
  if(!path.endsWith('404.html')) assert(!html.includes('content="noindex'),`Unexpected noindex: ${path}`);
}
const sitemap=await readFile(join(root,'sitemap-0.xml'),'utf8');
assert(!sitemap.includes('404'),'404 included in sitemap');
assert.equal((sitemap.match(/<loc>/g)||[]).length,12);
assert((await readFile(join(root,'robots.txt'),'utf8')).includes('Sitemap: https://zecbuyingprice.megabyte.sh/sitemap-index.xml'));
const home=await readFile(join(root,'index.html'),'utf8');
assert(home.includes('What does ZEC Buying Price calculate?'),'FAQ missing in raw HTML');
assert(home.includes('Synthetic transactions for illustration.'),'Screenshot disclosure missing');
console.log(JSON.stringify({pages:htmlFiles.length,uniqueTitles:titles.size,uniqueDescriptions:descriptions.size,localLinks:links,jsonLdBlocks:schemas,sitemapUrls:12,rawHtmlContent:'pass'},null,2));
