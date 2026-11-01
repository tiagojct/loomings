import { describe, it, expect } from 'vitest';
import { qrMatrix, qrSvg, qrVersion, formatBits, versionBits, qrPrintSide, MAXIMUM_BYTES } from './qr.js';

const bytes = (n) => 'a'.repeat(n);

describe('QR encoder', () => {
  it('refuses text over the native limit of 2,900 UTF-8 bytes', () => {
    expect(MAXIMUM_BYTES).toBe(2900);
    expect(qrMatrix(bytes(2900))).not.toBeNull();
    expect(qrMatrix(bytes(2901))).toBeNull();
    // Multibyte characters count as their UTF-8 bytes.
    expect(qrMatrix('é'.repeat(1450))).not.toBeNull();
    expect(qrMatrix('é'.repeat(1451))).toBeNull();
    expect(qrSvg(bytes(2901), 4)).toBeNull();
  });

  it('picks the smallest version that holds the bytes at level L', () => {
    expect(qrVersion(10)).toBe(1);
    expect(qrVersion(17)).toBe(1);
    expect(qrVersion(18)).toBe(2);
    expect(qrVersion(100)).toBe(5);
    expect(qrVersion(1000)).toBe(22);
    expect(qrVersion(1003)).toBe(22);
    expect(qrVersion(1004)).toBe(23);
    expect(qrVersion(2900)).toBe(40);
    expect(qrMatrix(bytes(100))?.length).toBe(17 + 4 * 5);
    expect(qrMatrix(bytes(2900))?.length).toBe(177);
  });

  it('has the published format and version bits', () => {
    const table = ['111011111000100', '111001011110011', '111110110101010', '111100010011101',
      '110011000101111', '110001100011000', '110110001000001', '110100101110110'];
    table.forEach((bits, mask) => expect(formatBits(mask).toString(2).padStart(15, '0')).toBe(bits));
    expect(versionBits(7)).toBe(0x07c94);
    expect(versionBits(8)).toBe(0x085bc);
    expect(versionBits(40)).toBe(0x28c69);
  });

  it('draws the finder patterns, timing lines and dark module', () => {
    const m = /** @type {boolean[][]} */ (qrMatrix('https://loomings.tiagojacinto.eu/app/'));
    const size = m.length;
    const finder = (x0, y0) => {
      for (let y = 0; y < 7; y++) {
        for (let x = 0; x < 7; x++) {
          const ring = Math.max(Math.abs(x - 3), Math.abs(y - 3));
          expect(m[y0 + y][x0 + x], `${x0 + x},${y0 + y}`).toBe(ring !== 2);
        }
      }
    };
    finder(0, 0);
    finder(size - 7, 0);
    finder(0, size - 7);
    for (let i = 8; i < size - 8; i++) {
      expect(m[6][i]).toBe(i % 2 === 0);
      expect(m[i][6]).toBe(i % 2 === 0);
    }
    expect(m[size - 8][8]).toBe(true);
  });

  it('writes the same format bits in both copies', () => {
    const m = /** @type {boolean[][]} */ (qrMatrix('Loomings'));
    const size = m.length;
    let first = 0;
    let second = 0;
    const firstCells = [[8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8], [7, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8]];
    firstCells.forEach(([x, y], i) => { if (m[y][x]) first |= 1 << i; });
    for (let i = 0; i < 8; i++) if (m[8][size - 1 - i]) second |= 1 << i;
    for (let i = 8; i < 15; i++) if (m[size - 15 + i][8]) second |= 1 << i;
    expect(first).toBe(second);
    expect([0, 1, 2, 3, 4, 5, 6, 7].map(formatBits)).toContain(first);
  });

  it('draws an SVG with a four-module quiet zone, in the current colour', () => {
    const svg = /** @type {string} */ (qrSvg('Hi', 4));
    expect(svg.startsWith('<svg')).toBe(true);
    expect(svg).toContain('viewBox="0 0 29 29"');
    expect(svg).toContain('width="116"');
    expect(svg).toContain('fill="currentColor"');
    expect(svg).not.toMatch(/#[0-9a-f]{3,6}/i);
  });

  it('prints at 1.6 points a module, between 72 and 300 points, as the native handout', () => {
    expect(qrPrintSide('Hi')).toBe(72);
    const dense = qrPrintSide(bytes(2900));
    expect(dense).toBeCloseTo((177 + 8) * 1.6, 5);
    expect(dense).toBeLessThanOrEqual(300);
    expect(qrPrintSide(bytes(2901))).toBeNull();
    expect(qrSvg('Hi', 4, '72pt')).toContain('width="72pt" height="72pt"');
  });
});
