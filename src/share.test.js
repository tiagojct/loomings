import { describe, it, expect } from 'vitest';
import { encodeDoc, decodeDoc, shareUrl, payloadFromUrl, canCompress } from './share.js';

const SAMPLE = `# Título com acentos\n\nÀ noite, *ninguém* escreve **assim** — ou escreve?\n\n- um\n- dois\n\n\`\`\`js\nconsole.log("olá");\n\`\`\`\n`;

describe('share links', () => {
  it('runs on a runtime with CompressionStream', () => {
    expect(canCompress).toBe(true);
  });

  it('round-trips text, including non-ASCII', async () => {
    expect(await decodeDoc(await encodeDoc(SAMPLE))).toBe(SAMPLE);
    expect(await decodeDoc(await encodeDoc(''))).toBe('');
    expect(await decodeDoc(await encodeDoc('🐋 emoji and — dashes'))).toBe('🐋 emoji and — dashes');
  });

  it('compresses repetitive documents and stays URL-safe', async () => {
    const big = 'Call me Ishmael. '.repeat(400);
    const payload = await encodeDoc(big);
    expect(payload.startsWith('z.')).toBe(true);
    expect(payload.length).toBeLessThan(big.length / 5);
    expect(payload).toMatch(/^[A-Za-z0-9._-]+$/);
  });

  it('also decodes the uncompressed form', async () => {
    const plain = 'p.' + btoa('hello').replace(/=+$/, '');
    expect(await decodeDoc(plain)).toBe('hello');
  });

  it('rejects malformed payloads', async () => {
    await expect(decodeDoc('nope')).rejects.toThrow();
    await expect(decodeDoc('x.abc')).rejects.toThrow();
  });

  it('builds a URL whose fragment carries the document and nothing else', async () => {
    const url = await shareUrl('# Hi', 'https://loomings.example/app/?lesson=basics#other');
    const u = new URL(url);
    expect(u.search).toBe('');
    expect(u.pathname).toBe('/app/');
    expect(payloadFromUrl(url)).not.toBeNull();
    expect(await decodeDoc(payloadFromUrl(url))).toBe('# Hi');
    expect(payloadFromUrl('https://loomings.example/app/')).toBeNull();
    expect(payloadFromUrl('https://loomings.example/app/#heading')).toBeNull();
  });

  // The native app has the same ceilings (ShareLink.maximumPayloadLength and
  // maximumDecodedLength). A link that is legal here must open there.
  it('refuses a payload over 4,000,000 bytes before decoding it', async () => {
    await expect(decodeDoc('z.' + 'A'.repeat(4_000_000))).rejects.toThrow(/too large/i);
  });

  it('refuses a compressed link that expands beyond 8,000,000 bytes', async () => {
    const bomb = new Uint8Array(8_000_001);
    const packed = new Uint8Array(await new Response(
      new Blob([bomb]).stream().pipeThrough(new CompressionStream('deflate-raw')),
    ).arrayBuffer());
    const payload = 'z.' + Buffer.from(packed).toString('base64url');
    expect(payload.length).toBeLessThan(4_000_000);
    await expect(decodeDoc(payload)).rejects.toThrow(/too large/i);
  });

  it('refuses to encode text over 8,000,000 bytes', async () => {
    await expect(encodeDoc('a'.repeat(8_000_001))).rejects.toThrow(/too large/i);
  });
});
