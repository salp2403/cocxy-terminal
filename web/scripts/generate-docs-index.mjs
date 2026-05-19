#!/usr/bin/env node
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, '..');
const publicRoot = path.join(webRoot, 'public');
const docsRoot = path.join(publicRoot, 'docs');
const output = path.join(docsRoot, 'search-index.json');

function stripHTML(value) {
  return value
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function textBetween(content, tag) {
  const match = content.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i'));
  return match ? stripHTML(match[1]) : '';
}

const entries = fs.readdirSync(docsRoot)
  .filter((name) => name.endsWith('.html') && name !== 'index.html')
  .sort()
  .map((name) => {
    const file = path.join(docsRoot, name);
    const esFile = path.join(publicRoot, 'es', 'docs', name);
    const html = fs.readFileSync(file, 'utf8');
    const esHTML = fs.existsSync(esFile) ? fs.readFileSync(esFile, 'utf8') : html;
    const slug = name.replace(/\.html$/, '');
    const title = textBetween(html, 'h1') || slug;
    const titleEs = textBetween(esHTML, 'h1') || title;
    const summaryMatch = html.match(/<meta name="description" content="([^"]+)"/i);
    const summaryEsMatch = esHTML.match(/<meta name="description" content="([^"]+)"/i);
    const summary = summaryMatch ? summaryMatch[1] : '';
    const summaryEs = summaryEsMatch ? summaryEsMatch[1] : summary;
    const headings = [...html.matchAll(/<h2[^>]*>([\s\S]*?)<\/h2>/gi)].map((match) => stripHTML(match[1]));
    const headingsEs = [...esHTML.matchAll(/<h2[^>]*>([\s\S]*?)<\/h2>/gi)].map((match) => stripHTML(match[1]));
    return {
      title,
      titleEs,
      url: `/docs/${name}`,
      urlEs: `/es/docs/${name}`,
      summary,
      summaryEs,
      terms: [slug, title, titleEs, summary, summaryEs, ...headings, ...headingsEs].join(' ').toLowerCase(),
    };
  });

fs.writeFileSync(output, `${JSON.stringify(entries, null, 2)}\n`);
console.log(`Generated ${path.relative(webRoot, output)} with ${entries.length} entries`);
