// Serves the site the way nginx does in production: the landing page at /,
// the built app at /app/ (so the landing page can load /app/fonts). Run
// `npm run build` first for the app half.
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const docs = join(root, 'docs');
const dist = join(root, 'dist');
const vendor = join(root, 'vendor');
const port = Number(process.env.PORT || 8080);
const types = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript',
  '.woff2': 'font/woff2', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.webmanifest': 'application/manifest+json', '.json': 'application/json',
};

http.createServer(async (req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  const isApp = url.startsWith('/app/');
  const isVendor = url.startsWith('/vendor/');
  const rel = normalize(isApp ? url.slice(5) : isVendor ? url.slice(8) : url === '/' ? 'index.html' : url.slice(1));
  if (rel.startsWith('..')) { res.writeHead(403).end(); return; }
  const file = join(isApp ? dist : isVendor ? vendor : docs, !rel || rel === '.' ? 'index.html' : rel);
  try {
    const data = await readFile(file);
    res.writeHead(200, { 'content-type': types[extname(file)] || 'application/octet-stream' });
    res.end(data);
  } catch {
    res.writeHead(404, { 'content-type': 'text/plain' }).end('404 ' + url);
  }
}).listen(port, '127.0.0.1', () => console.log(`site on http://127.0.0.1:${port}/`));
