// ========================================
// Loomings — QR codes for share links
// A small encoder: byte mode, error correction level L, versions 1 to 40,
// the mask with the lowest penalty (ISO/IEC 18004). Written here because the
// app has no network and takes no new dependency. Links above 2,900 UTF-8
// bytes are refused, as in the native app (ShareQRCode.maximumBytes).
// macos/Tests/LoomingsShareTests decodes this encoder's output with
// CoreImage, so a phone can read what it draws.
// ========================================

export const MAXIMUM_BYTES = 2900;

// Level L, indexed by version (index 0 unused).
const ECC_PER_BLOCK = [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28,
  28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30];
const BLOCKS = [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8,
  8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25];
const FORMAT_L = 1;

/** Modules that carry data or error correction, for a version. */
function rawDataModules(version) {
  let result = (16 * version + 128) * version + 64;
  if (version >= 2) {
    const align = Math.floor(version / 7) + 2;
    result -= (25 * align - 10) * align - 55;
    if (version >= 7) result -= 36;
  }
  return result;
}

/** Data codewords a version holds at level L. */
function dataCodewords(version) {
  return Math.floor(rawDataModules(version) / 8) - ECC_PER_BLOCK[version] * BLOCKS[version];
}

/**
 * The smallest version that holds `length` bytes in byte mode, or 0.
 *
 * @param {number} length
 * @returns {number}
 */
export function qrVersion(length) {
  for (let version = 1; version <= 40; version++) {
    const countBits = version < 10 ? 8 : 16;
    if (4 + countBits + length * 8 <= dataCodewords(version) * 8) return version;
  }
  return 0;
}

/** The 15 format bits for level L and `mask`, BCH protected and masked. */
export function formatBits(mask) {
  const data = (FORMAT_L << 3) | mask;
  let rem = data;
  for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
  return ((data << 10) | rem) ^ 0x5412;
}

/** The 18 version bits for versions 7 and up. */
export function versionBits(version) {
  let rem = version;
  for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
  return (version << 12) | rem;
}

// ---------- Reed-Solomon over GF(256), polynomial 0x11D ----------

function multiply(x, y) {
  let z = 0;
  for (let i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d);
    z ^= ((y >>> i) & 1) * x;
  }
  return z;
}

function divisor(degree) {
  const result = new Array(degree).fill(0);
  result[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < degree; j++) {
      result[j] = multiply(result[j], root);
      if (j + 1 < degree) result[j] ^= result[j + 1];
    }
    root = multiply(root, 0x02);
  }
  return result;
}

function remainder(data, div) {
  const result = new Array(div.length).fill(0);
  for (const b of data) {
    const factor = b ^ /** @type {number} */ (result.shift());
    result.push(0);
    div.forEach((coef, i) => { result[i] ^= multiply(coef, factor); });
  }
  return result;
}

// ---------- Encoding ----------

/** Data and error correction codewords, interleaved. */
function codewords(bytes, version) {
  const capacity = dataCodewords(version);
  /** @type {number[]} */
  const bits = [];
  const put = (value, length) => { for (let i = length - 1; i >= 0; i--) bits.push((value >>> i) & 1); };
  put(0b0100, 4);
  put(bytes.length, version < 10 ? 8 : 16);
  for (const b of bytes) put(b, 8);
  put(0, Math.min(4, capacity * 8 - bits.length));
  put(0, (8 - (bits.length % 8)) % 8);
  for (let pad = 0xec; bits.length < capacity * 8; pad ^= 0xec ^ 0x11) put(pad, 8);
  const data = [];
  for (let i = 0; i < bits.length; i += 8) data.push(bits.slice(i, i + 8).reduce((a, b) => (a << 1) | b, 0));

  const numBlocks = BLOCKS[version];
  const eccLength = ECC_PER_BLOCK[version];
  const raw = Math.floor(rawDataModules(version) / 8);
  const numShort = numBlocks - (raw % numBlocks);
  const shortLength = Math.floor(raw / numBlocks);
  const div = divisor(eccLength);
  /** @type {number[][]} */
  const blocks = [];
  for (let i = 0, k = 0; i < numBlocks; i++) {
    const dat = data.slice(k, k + shortLength - eccLength + (i < numShort ? 0 : 1));
    k += dat.length;
    const ecc = remainder(dat, div);
    if (i < numShort) dat.push(0);
    blocks.push(dat.concat(ecc));
  }
  const result = [];
  for (let i = 0; i < blocks[0].length; i++) {
    blocks.forEach((block, j) => {
      if (i !== shortLength - eccLength || j >= numShort) result.push(block[i]);
    });
  }
  return result;
}

function alignmentPositions(version) {
  if (version === 1) return [];
  const count = Math.floor(version / 7) + 2;
  const size = version * 4 + 17;
  const step = Math.floor((version * 8 + count * 3 + 5) / (count * 4 - 4)) * 2;
  const result = [6];
  for (let pos = size - 7; result.length < count; pos -= step) result.splice(1, 0, pos);
  return result;
}

const MASKS = [
  (x, y) => (x + y) % 2 === 0,
  (x, y) => y % 2 === 0,
  (x) => x % 3 === 0,
  (x, y) => (x + y) % 3 === 0,
  (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
  (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
  (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
  (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0,
];

/**
 * The QR code for `text` as rows of dark (true) and light modules, without
 * the quiet zone; null above MAXIMUM_BYTES.
 *
 * @param {string} text
 * @returns {boolean[][]|null}
 */
export function qrMatrix(text) {
  const bytes = new TextEncoder().encode(text);
  if (bytes.length > MAXIMUM_BYTES) return null;
  const version = qrVersion(bytes.length);
  if (!version) return null;
  const size = version * 4 + 17;
  const modules = Array.from({ length: size }, () => new Array(size).fill(false));
  const isFunction = Array.from({ length: size }, () => new Array(size).fill(false));
  const set = (x, y, dark) => { modules[y][x] = dark; isFunction[y][x] = true; };

  for (let i = 0; i < size; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0); }
  for (const [cx, cy] of [[3, 3], [size - 4, 3], [3, size - 4]]) {
    for (let dy = -4; dy <= 4; dy++) {
      for (let dx = -4; dx <= 4; dx++) {
        const x = cx + dx;
        const y = cy + dy;
        const ring = Math.max(Math.abs(dx), Math.abs(dy));
        if (x >= 0 && x < size && y >= 0 && y < size) set(x, y, ring !== 2 && ring !== 4);
      }
    }
  }
  const align = alignmentPositions(version);
  align.forEach((ax, i) => align.forEach((ay, j) => {
    const corner = (i === 0 && j === 0) || (i === 0 && j === align.length - 1) || (i === align.length - 1 && j === 0);
    if (corner) return;
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(ax + dx, ay + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
  }));
  const drawFormat = (mask) => {
    const bits = formatBits(mask);
    const bit = (i) => ((bits >>> i) & 1) !== 0;
    for (let i = 0; i <= 5; i++) set(8, i, bit(i));
    set(8, 7, bit(6));
    set(8, 8, bit(7));
    set(7, 8, bit(8));
    for (let i = 9; i < 15; i++) set(14 - i, 8, bit(i));
    for (let i = 0; i < 8; i++) set(size - 1 - i, 8, bit(i));
    for (let i = 8; i < 15; i++) set(8, size - 15 + i, bit(i));
    set(8, size - 8, true);
  };
  drawFormat(0);
  if (version >= 7) {
    const bits = versionBits(version);
    for (let i = 0; i < 18; i++) {
      const dark = ((bits >>> i) & 1) !== 0;
      const a = size - 11 + (i % 3);
      const b = Math.floor(i / 3);
      set(a, b, dark);
      set(b, a, dark);
    }
  }

  const data = codewords(bytes, version);
  let i = 0;
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5;
    for (let vert = 0; vert < size; vert++) {
      for (let j = 0; j < 2; j++) {
        const x = right - j;
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? size - 1 - vert : vert;
        if (!isFunction[y][x] && i < data.length * 8) {
          modules[y][x] = ((data[i >>> 3] >>> (7 - (i & 7))) & 1) !== 0;
          i++;
        }
      }
    }
  }

  const applyMask = (mask) => {
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) if (!isFunction[y][x] && MASKS[mask](x, y)) modules[y][x] = !modules[y][x];
    }
  };
  let best = 0;
  let bestScore = Infinity;
  for (let mask = 0; mask < 8; mask++) {
    applyMask(mask);
    drawFormat(mask);
    const score = penalty(modules);
    if (score < bestScore) { best = mask; bestScore = score; }
    applyMask(mask);
  }
  applyMask(best);
  drawFormat(best);
  return modules;
}

/** The standard penalty: runs, 2x2 blocks, finder-like patterns, balance. */
function penalty(modules) {
  const size = modules.length;
  let result = 0;
  const addHistory = (length, history) => {
    if (history[0] === 0) length += size;
    history.pop();
    history.unshift(length);
  };
  const countPatterns = (h) => {
    const n = h[1];
    const core = n > 0 && h[2] === n && h[3] === n * 3 && h[4] === n && h[5] === n;
    return (core && h[0] >= n * 4 && h[6] >= n ? 1 : 0) + (core && h[6] >= n * 4 && h[0] >= n ? 1 : 0);
  };
  const terminate = (color, length, history) => {
    if (color) { addHistory(length, history); length = 0; }
    addHistory(length + size, history);
    return countPatterns(history);
  };
  for (const vertical of [false, true]) {
    for (let a = 0; a < size; a++) {
      let color = false;
      let run = 0;
      const history = [0, 0, 0, 0, 0, 0, 0];
      for (let b = 0; b < size; b++) {
        const dark = vertical ? modules[b][a] : modules[a][b];
        if (dark === color) {
          run++;
          if (run === 5) result += 3;
          else if (run > 5) result++;
        } else {
          addHistory(run, history);
          if (!color) result += countPatterns(history) * 40;
          color = dark;
          run = 1;
        }
      }
      result += terminate(color, run, history) * 40;
    }
  }
  let dark = 0;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (modules[y][x]) dark++;
      if (y < size - 1 && x < size - 1) {
        const c = modules[y][x];
        if (c === modules[y][x + 1] && c === modules[y + 1][x] && c === modules[y + 1][x + 1]) result += 3;
      }
    }
  }
  const total = size * size;
  result += (Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1) * 10;
  return result;
}

/**
 * The side to print a code at, in points: 1.6 points a module (quiet zone
 * included) so a phone reads it from paper, never below 72 or above 300, as
 * the native handout. Null above MAXIMUM_BYTES.
 *
 * @param {string} text
 * @returns {number|null}
 */
export function qrPrintSide(text) {
  const matrix = qrMatrix(text);
  return matrix ? Math.min(300, Math.max(72, (matrix.length + 8) * 1.6)) : null;
}

/**
 * The QR code as an SVG in the current text colour, with a four-module
 * quiet zone, or null above MAXIMUM_BYTES.
 *
 * @param {string} text
 * @param {number} modulePx
 * @param {string} [side] a CSS length that replaces the pixel size
 * @returns {string|null}
 */
export function qrSvg(text, modulePx, side) {
  const matrix = qrMatrix(text);
  if (!matrix) return null;
  const modules = matrix.length + 8;
  let path = '';
  matrix.forEach((row, y) => row.forEach((dark, x) => { if (dark) path += `M${x + 4} ${y + 4}h1v1h-1z`; }));
  const length = side || String(modules * modulePx);
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${modules} ${modules}" width="${length}" height="${length}" shape-rendering="crispEdges" role="img" aria-label="QR code">`
    + `<path fill="currentColor" d="${path}"/></svg>`;
}
