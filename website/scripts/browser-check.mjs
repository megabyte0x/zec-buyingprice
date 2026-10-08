import { chromium } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { mkdir, writeFile } from 'node:fs/promises';
const url=process.env.SITE_URL||'http://127.0.0.1:4321';
const browser=await chromium.launch({headless:true});
const results=[];
await mkdir('/tmp/zec-site-reference/screenshots',{recursive:true});
for(const colorScheme of ['light','dark']){
 for(const width of [390,1440]){
  const context=await browser.newContext({viewport:{width,height:1000},colorScheme});
  const page=await context.newPage();
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(url,{waitUntil:'networkidle'});
  await page.screenshot({path:`/tmp/zec-site-reference/screenshots/home-${colorScheme}-${width}.png`,fullPage:true});
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
  const trigger=page.getByRole('button',{name:'What does ZEC Buying Price calculate?'});
  await trigger.click();await page.waitForTimeout(250);
  if(await trigger.getAttribute('aria-expanded')!=='false')throw Error('FAQ did not collapse');
  await trigger.click();await page.waitForTimeout(250);
  if(await trigger.getAttribute('aria-expanded')!=='true')throw Error('FAQ did not reopen');
  const accessibility=await new AxeBuilder({page}).withTags(['wcag2a','wcag2aa','wcag21aa','wcag22aa']).analyze();
  results.push({colorScheme,width,overflow,errors,violations:accessibility.violations.map(v=>({id:v.id,impact:v.impact,nodes:v.nodes.map(n=>n.target)}))});
  await context.close();
 }
}
for(const path of ['/blog/zcash-tracker-alternatives/','/releases/','/setup/']){
 const context=await browser.newContext({viewport:{width:390,height:844}});const page=await context.newPage();await page.goto(url+path,{waitUntil:'networkidle'});
 const accessibility=await new AxeBuilder({page}).withTags(['wcag2a','wcag2aa','wcag21aa','wcag22aa']).analyze();
 const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
 results.push({path,width:390,overflow,violations:accessibility.violations.map(v=>({id:v.id,nodes:v.nodes.map(n=>n.target)}))});await context.close();
}
await browser.close();await writeFile('/tmp/zec-site-reference/browser-results.json',JSON.stringify(results,null,2));console.log(JSON.stringify(results,null,2));
if(results.some(r=>r.overflow||r.errors?.length||r.violations.length))process.exitCode=1;
