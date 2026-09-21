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
});
