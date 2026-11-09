// ========================================
// Loomings — share links
// A document travels inside the URL fragment: `#d=z.<base64url deflate>`
// (or `#d=p.<base64url utf-8>` where CompressionStream is missing). The
// fragment never reaches the server, so sharing stays private and needs
// no backend. Pure functions; used by editor.js and the tests.
// ========================================

const PARAM = 'd';

// The same ceilings as the native app (ShareLink.maximumPayloadLength and
// maximumDecodedLength): a link the web makes must open there, and a link the
// web opens cannot expand without a bound in memory.
export const MAXIMUM_PAYLOAD_BYTES = 4_000_000;
export const MAXIMUM_DECODED_BYTES = 8_000_000;

const TOO_LARGE_TO_OPEN = 'This share link is too large to open safely.';
const TOO_LARGE_TO_SHARE = 'This document is too large to share as a link.';

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

// Decompresses with a ceiling. The reader is read chunk by chunk, so a
// compressed link cannot expand past the limit before the check runs.
async function inflateLimited(bytes) {
  const res = new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate-raw')));
  const reader = res.body?.getReader();
  if (!reader) throw new Error('Malformed share link');
  /** @type {Uint8Array[]} */
  const chunks = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAXIMUM_DECODED_BYTES) throw new Error(TOO_LARGE_TO_OPEN);
      chunks.push(value);
    }
  } catch (err) {
    reader.cancel().catch(() => {});
    throw err;
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const chunk of chunks) {
    out.set(chunk, at);
    at += chunk.byteLength;
  }
  return out;
}

export const canCompress = typeof CompressionStream === 'function' && typeof DecompressionStream === 'function';

// Text → the value that goes after `#d=`.
export async function encodeDoc(text) {
  const raw = new TextEncoder().encode(text);
  if (raw.length > MAXIMUM_DECODED_BYTES) throw new Error(TOO_LARGE_TO_SHARE);
  const payload = canCompress
    ? 'z.' + bytesToBase64Url(await pipe(raw, new CompressionStream('deflate-raw')))
    : 'p.' + bytesToBase64Url(raw);
  if (payload.length > MAXIMUM_PAYLOAD_BYTES) throw new Error(TOO_LARGE_TO_SHARE);
  return payload;
}

// The value after `#d=` → text. Throws on a malformed payload.
export async function decodeDoc(payload) {
  if (typeof payload !== 'string') throw new Error('Malformed share link');
  if (payload.length > MAXIMUM_PAYLOAD_BYTES) throw new Error(TOO_LARGE_TO_OPEN);
  const dot = payload.indexOf('.');
  if (dot !== 1) throw new Error('Malformed share link');
  const kind = payload[0];
  const bytes = base64UrlToBytes(payload.slice(2));
  if (kind === 'p') {
    if (bytes.length > MAXIMUM_DECODED_BYTES) throw new Error(TOO_LARGE_TO_OPEN);
    return new TextDecoder().decode(bytes);
  }
  if (kind === 'z') {
    if (!canCompress) throw new Error('This browser cannot open compressed share links');
    return new TextDecoder().decode(await inflateLimited(bytes));
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
