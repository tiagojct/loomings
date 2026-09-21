// ========================================
// Loomings — share links
// A document travels inside the URL fragment: `#d=z.<base64url deflate>`
// (or `#d=p.<base64url utf-8>` where CompressionStream is missing). The
// fragment never reaches the server, so sharing stays private and needs
// no backend. Pure functions; used by editor.js and the tests.
// ========================================

const PARAM = 'd';

function bytesToBase64Url(bytes) {
  let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  }
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlToBytes(str) {
  const b64 = str.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (str.length % 4)) % 4);
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function pipe(bytes, stream) {
  const res = new Response(new Blob([bytes]).stream().pipeThrough(stream));
  return new Uint8Array(await res.arrayBuffer());
}

export const canCompress = typeof CompressionStream === 'function' && typeof DecompressionStream === 'function';

// Text → the value that goes after `#d=`.
export async function encodeDoc(text) {
  const raw = new TextEncoder().encode(text);
  if (canCompress) {
    const packed = await pipe(raw, new CompressionStream('deflate-raw'));
    return 'z.' + bytesToBase64Url(packed);
  }
  return 'p.' + bytesToBase64Url(raw);
}

// The value after `#d=` → text. Throws on a malformed payload.
export async function decodeDoc(payload) {
  const dot = payload.indexOf('.');
  if (dot !== 1) throw new Error('Malformed share link');
  const kind = payload[0];
  const bytes = base64UrlToBytes(payload.slice(2));
  if (kind === 'p') return new TextDecoder().decode(bytes);
  if (kind === 'z') {
    if (!canCompress) throw new Error('This browser cannot open compressed share links');
    return new TextDecoder().decode(await pipe(bytes, new DecompressionStream('deflate-raw')));
  }
  throw new Error('Unknown share link format');
}

// Full URL for `text` at the current app location.
export async function shareUrl(text, base) {
  const u = new URL(base);
  u.search = '';
  u.hash = `${PARAM}=${await encodeDoc(text)}`;
  return u.toString();
}

// The share payload carried by a URL, or null when it has none.
export function payloadFromUrl(href) {
  const hash = new URL(href).hash.replace(/^#/, '');
  if (!hash) return null;
  const params = new URLSearchParams(hash);
  return params.get(PARAM);
}
