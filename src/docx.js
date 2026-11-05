// ========================================
// Loomings — DOCX export
// Turns the rendered, sanitised HTML of a document (citations and reference
// list included) into a Word file. Paragraphs use the built-in Word style ids
// (Title, Heading1-6, Quote, Bibliography, SourceCode, Hyperlink), so a Word
// template restyles the file. The docx library loads on demand.
// Browser code: needs DOMParser, or a `parse` function in the options.
// ========================================

import { SAFE_URL } from './markdown.js';

/**
 * @typedef {{data: Uint8Array, type: 'png'|'jpg'|'gif'|'bmp', width: number, height: number}} LoadedImage
 * @typedef {{src: string, alt: string} | {svg: string, alt: string}} ImageSource
 * @typedef {{
 *   title?: string|null,
 *   lang?: string|null,
 *   paper?: 'A4'|'letter',
 *   parse?: (html: string) => ParentNode & {body?: HTMLElement},
 *   loadImage?: (source: ImageSource) => Promise<LoadedImage|null>,
 * }} DocxOptions
 */

const MAX_IMAGE_WIDTH = 600; // pixels at 96 dpi, the text width of an A4 page with 2.5 cm margins
const BLOCK = new Set([
  'p', 'div', 'section', 'blockquote', 'pre', 'ul', 'ol', 'li', 'table', 'hr', 'figure',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
]);
const HEADINGS = ['HEADING_1', 'HEADING_2', 'HEADING_3', 'HEADING_4', 'HEADING_5', 'HEADING_6'];
const BODY_FONT = 'Georgia';
const CODE_FONT = 'Consolas';

/** The tag name in lower case. @param {Node} node */
const tag = (node) => (node.nodeType === 1 ? /** @type {Element} */ (node).tagName.toLowerCase() : '');

/** @param {Element} el @param {string} name */
const hasClass = (el, name) => (el.getAttribute('class') ?? '').split(/\s+/).includes(name);

/** @param {string} text */
const trimLine = (text) => text.replace(/ /g, ' ');

/**
 * Builds the .docx file.
 *
 * @param {string} html  rendered HTML: markdown-it output plus the reference list
 * @param {DocxOptions} [options]
 * @returns {Promise<Blob>}
 */
export async function htmlToDocx(html, options = {}) {
  const docx = await import('docx');
  const parse = options.parse ?? ((/** @type {string} */ source) => new DOMParser().parseFromString(source, 'text/html'));
  const root = parse(html);
  const body = root.body ?? /** @type {ParentNode} */ (root);
  const loadImage = options.loadImage ?? (async () => null);

  const {
    Document, Packer, Paragraph, TextRun, ExternalHyperlink, ImageRun, Table, TableRow, TableCell,
    WidthType, HeadingLevel, Tab, BorderStyle, LevelFormat, AlignmentType, PageOrientation,
  } = docx;

  /** @type {{reference: string, levels: any[]}[]} */
  const numberingConfig = [];
  let listCount = 0;

  /** @param {boolean} ordered */
  function newList(ordered) {
    const reference = `${ordered ? 'ol' : 'ul'}-${++listCount}`;
    const levels = [];
    for (let level = 0; level < 6; level++) {
      levels.push({
        level,
        format: ordered ? LevelFormat.DECIMAL : LevelFormat.BULLET,
        text: ordered ? `%${level + 1}.` : ['•', '◦', '▪'][level % 3],
        alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720 * (level + 1), hanging: 360 } } },
      });
    }
    numberingConfig.push({ reference, levels });
    return reference;
  }

  // ----- inline -----

  /**
   * @typedef {{bold?: boolean, italics?: boolean, strike?: boolean, code?: boolean,
   *   sup?: boolean, sub?: boolean, link?: string|null}} Marks
   */

  /**
   * @param {string} text
   * @param {Marks} marks
   */
  function run(text, marks) {
    return new TextRun({
      text,
      bold: marks.bold || undefined,
      italics: marks.italics || undefined,
      strike: marks.strike || undefined,
      superScript: marks.sup || undefined,
      subScript: marks.sub || undefined,
      font: marks.code ? CODE_FONT : undefined,
      size: marks.code ? 20 : undefined,
      style: marks.link ? 'Hyperlink' : undefined,
    });
  }

  /**
   * Converts inline nodes to Word runs. Images load asynchronously.
   *
   * @param {Node[]} nodes
   * @param {Marks} marks
   * @returns {Promise<any[]>}
   */
  async function inline(nodes, marks) {
    /** @type {any[]} */
    const out = [];
    for (const node of nodes) {
      if (node.nodeType === 3) {
        const text = (node.textContent ?? '').replace(/\s*\n\s*/g, ' ');
        if (text) out.push(run(text, marks));
        continue;
      }
      if (node.nodeType !== 1) continue;
      const el = /** @type {Element} */ (node);
      const name = tag(el);
      const kids = Array.from(el.childNodes);
      if (name === 'br') {
        out.push(new TextRun({ break: 1 }));
      } else if (name === 'strong' || name === 'b') {
        out.push(...(await inline(kids, { ...marks, bold: true })));
      } else if (name === 'em' || name === 'i') {
        out.push(...(await inline(kids, { ...marks, italics: true })));
      } else if (name === 's' || name === 'del') {
        out.push(...(await inline(kids, { ...marks, strike: true })));
      } else if (name === 'code') {
        out.push(...(await inline(kids, { ...marks, code: true })));
      } else if (name === 'sup') {
        out.push(...(await inline(kids, { ...marks, sup: true })));
      } else if (name === 'sub') {
        out.push(...(await inline(kids, { ...marks, sub: true })));
      } else if (name === 'a') {
        const href = el.getAttribute('href') ?? '';
        const children = await inline(kids, { ...marks, link: href });
        if (SAFE_URL.test(href) && /^(https?:|mailto:)/i.test(href)) {
          out.push(new ExternalHyperlink({ link: href, children }));
        } else {
          out.push(...children);
        }
      } else if (name === 'img') {
        out.push(...(await imageRuns(el)));
      } else if (name === 'svg') {
        out.push(...(await svgRuns(el)));
      } else {
        // span and any other inline element: keep the text and the marks.
        out.push(...(await inline(kids, marks)));
      }
    }
    return out;
  }

  /** @param {LoadedImage} image */
  function imageRun(image, alt) {
    const scale = image.width > MAX_IMAGE_WIDTH ? MAX_IMAGE_WIDTH / image.width : 1;
    return new ImageRun({
      type: image.type,
      data: image.data,
      transformation: { width: Math.max(1, Math.round(image.width * scale)), height: Math.max(1, Math.round(image.height * scale)) },
      altText: { name: alt || 'image', title: alt || 'image', description: alt || 'image' },
    });
  }

  /** @param {Element} el */
  async function imageRuns(el) {
    const alt = el.getAttribute('alt') ?? '';
    const src = el.getAttribute('src') ?? '';
    const image = src && src !== '#' ? await loadImage({ src, alt }).catch(() => null) : null;
    if (image) return [imageRun(image, alt)];
    return [new TextRun({ text: `[image${alt ? ': ' + alt : ''}]`, italics: true })];
  }

  /** @param {Element} el */
  async function svgRuns(el) {
    const alt = el.getAttribute('aria-label') ?? el.querySelector('title')?.textContent ?? 'diagram';
    const image = await loadImage({ svg: el.outerHTML, alt }).catch(() => null);
    if (image) return [imageRun(image, alt)];
    return [new TextRun({ text: `[${alt}]`, italics: true })];
  }

  // ----- blocks -----

  /**
   * @typedef {{style?: string, list?: {reference: string, level: number}, used?: {value: boolean},
   *   indent?: number}} Ctx
   */

  /**
   * One paragraph from inline nodes.
   *
   * @param {Node[]} nodes
   * @param {Ctx} ctx
   * @param {object} [extra]
   */
  async function paragraph(nodes, ctx, extra = {}) {
    const children = await inline(nodes, {});
    /** @type {Record<string, unknown>} */
    const props = { children, ...extra };
    if (ctx.style && !props.style) props.style = ctx.style;
    if (ctx.list && ctx.used && !ctx.used.value) {
      props.numbering = { reference: ctx.list.reference, level: ctx.list.level };
      ctx.used.value = true;
    } else if (ctx.list) {
      props.indent = { left: 720 * (ctx.list.level + 1) };
    }
    return new Paragraph(/** @type {any} */ (props));
  }

  /**
   * Converts the children of a container. Runs of inline nodes become one paragraph.
   *
   * @param {Node[]} nodes
   * @param {Ctx} ctx
   * @returns {Promise<any[]>}
   */
  async function blocks(nodes, ctx) {
    /** @type {any[]} */
    const out = [];
    /** @type {Node[]} */
    let pending = [];
    const flush = async () => {
      const text = pending.map((n) => n.textContent ?? '').join('');
      const hasMedia = pending.some((n) => n.nodeType === 1 && ['img', 'svg'].includes(tag(n)));
      if (text.trim() || hasMedia) out.push(await paragraph(trimmed(pending), ctx));
      pending = [];
    };
    for (const node of nodes) {
      const name = tag(node);
      if (node.nodeType === 1 && (BLOCK.has(name) || (name === 'svg'))) {
        await flush();
        out.push(...(await block(/** @type {Element} */ (node), ctx)));
      } else {
        pending.push(node);
      }
    }
    await flush();
    return out;
  }

  /** Drops edge whitespace-only text nodes of a paragraph. @param {Node[]} nodes */
  function trimmed(nodes) {
    const list = nodes.slice();
    while (list.length && list[0].nodeType === 3 && !(list[0].textContent ?? '').trim()) list.shift();
    while (list.length && list[list.length - 1].nodeType === 3 && !(list[list.length - 1].textContent ?? '').trim()) list.pop();
    return list;
  }

  /**
   * @param {Element} el
   * @param {Ctx} ctx
   * @returns {Promise<any[]>}
   */
  async function block(el, ctx) {
    const name = tag(el);
    const kids = Array.from(el.childNodes);
    const heading = /^h([1-6])$/.exec(name);
    if (heading) {
      const level = Number(heading[1]);
      return [await paragraph(kids, { ...ctx, list: undefined }, { heading: HeadingLevel[/** @type {'HEADING_1'} */ (HEADINGS[level - 1])] })];
    }
    switch (name) {
      case 'p':
        return [await paragraph(kids, ctx)];
      case 'blockquote':
        return blocks(kids, { ...ctx, style: 'Quote' });
      case 'ul':
      case 'ol':
        return list(el, ctx);
      case 'pre':
        return pre(el, ctx);
      case 'hr':
        return [new Paragraph({
          children: [],
          border: { bottom: { style: BorderStyle.SINGLE, size: 6, space: 1, color: '999999' } },
          spacing: { before: 200, after: 200 },
        })];
      case 'table':
        return [await table(el), new Paragraph({ children: [] })];
      case 'svg':
        return [new Paragraph({ children: await svgRuns(el), alignment: AlignmentType.CENTER })];
      case 'div':
        if (hasClass(el, 'csl-entry')) return [await bibliographyEntry(el)];
        return blocks(kids, ctx);
      case 'li':
        return blocks(kids, ctx);
      default: // section, figure
        return blocks(kids, ctx);
    }
  }

  /**
   * @param {Element} el  ul or ol
   * @param {Ctx} ctx
   */
  async function list(el, ctx) {
    const ordered = tag(el) === 'ol';
    const level = ctx.list ? ctx.list.level + 1 : 0;
    // A nested list continues the numbering definition of its parent only if
    // it is the same kind; a new definition keeps each numbered list at 1.
    const reference = ordered || !ctx.list || ctx.list.reference.startsWith('ol-') ? newList(ordered) : ctx.list.reference;
    /** @type {any[]} */
    const out = [];
    for (const item of Array.from(el.children)) {
      if (tag(item) !== 'li') continue;
      out.push(...(await blocks(Array.from(item.childNodes), {
        style: ctx.style,
        list: { reference, level: Math.min(level, 5) },
        used: { value: false },
      })));
    }
    return out;
  }

  /** @param {Element} el @param {Ctx} ctx */
  async function pre(el, ctx) {
    if (hasClass(el, 'mermaid')) {
      const svg = el.querySelector('svg');
      if (svg) return [new Paragraph({ children: await svgRuns(svg), alignment: AlignmentType.CENTER })];
    }
    const text = (el.textContent ?? '').replace(/\n$/, '');
    const lines = text.split('\n');
    const out = lines.map((line, i) => new Paragraph({
      style: 'SourceCode',
      children: [new TextRun({ text: line || ' ', font: CODE_FONT })],
      keepNext: i < lines.length - 1 && lines.length < 12,
      spacing: i === lines.length - 1 ? { after: 160 } : undefined,
    }));
    if (hasClass(el, 'mermaid-error')) {
      const note = el.querySelector('p')?.textContent;
      if (note) out.push(new Paragraph({ children: [new TextRun({ text: note, italics: true })] }));
    }
    return out;
  }

  /** @param {Element} el */
  async function bibliographyEntry(el) {
    const left = Array.from(el.children).find((c) => hasClass(c, 'csl-left-margin'));
    const right = Array.from(el.children).find((c) => hasClass(c, 'csl-right-inline'));
    if (left && right) {
      const children = [
        ...(await inline(Array.from(left.childNodes), {})),
        new TextRun({ children: [new Tab()] }),
        ...(await inline(Array.from(right.childNodes), {})),
      ];
      return new Paragraph({ style: 'Bibliography', children, tabStops: [{ type: 'left', position: 540 }] });
    }
    return new Paragraph({ style: 'Bibliography', children: await inline(Array.from(el.childNodes), {}) });
  }

  /** @param {Element} el */
  async function table(el) {
    const rows = [];
    for (const tr of Array.from(el.querySelectorAll('tr'))) {
      const cells = [];
      const isHeader = tr.parentElement ? tag(tr.parentElement) === 'thead' : false;
      for (const cell of Array.from(tr.children)) {
        const th = tag(cell) === 'th';
        const align = /text-align:\s*(left|right|center)/.exec(cell.getAttribute('style') ?? '')?.[1];
        const children = await inline(Array.from(cell.childNodes), th ? { bold: true } : {});
        cells.push(new TableCell({
          children: [new Paragraph({
            children,
            alignment: align === 'right' ? AlignmentType.RIGHT : align === 'center' ? AlignmentType.CENTER : AlignmentType.LEFT,
          })],
          margins: { top: 60, bottom: 60, left: 100, right: 100 },
        }));
      }
      if (cells.length) rows.push(new TableRow({ children: cells, tableHeader: isHeader, cantSplit: true }));
    }
    return new Table({ rows, width: { size: 100, type: WidthType.PERCENTAGE } });
  }

  // ----- document -----

  const children = await blocks(Array.from(body.childNodes), {});

  // A title in the frontmatter becomes the Title paragraph, unless the text
  // opens with the same heading.
  const title = options.title?.trim();
  if (title) {
    const first = body.querySelector ? body.querySelector('h1') : null;
    const firstOpens = first && body.firstElementChild === first;
    if (!firstOpens || trimLine(first?.textContent ?? '').trim() !== title) {
      children.unshift(new Paragraph({ style: 'Title', children: [new TextRun({ text: title })] }));
    }
  }
  if (!children.length) children.push(new Paragraph({ children: [] }));

  const letter = options.paper === 'letter';
  const heading = (/** @type {number} */ size, /** @type {number} */ before) => ({
    run: { font: BODY_FONT, size, bold: true, color: '1F1F1F' },
    paragraph: { spacing: { before, after: 120 }, keepNext: true },
  });
  const style = (/** @type {string} */ id, /** @type {string} */ name, /** @type {object} */ extra) => ({
    id, name, basedOn: 'Normal', next: 'Normal', quickFormat: true, ...extra,
  });

  const document = new Document({
    creator: 'Loomings',
    title: title || undefined,
    numbering: { config: numberingConfig },
    styles: {
      default: {
        document: {
          run: { font: BODY_FONT, size: 22, language: { value: options.lang || 'en-US' } },
          paragraph: { spacing: { after: 140, line: 300 } },
        },
      },
      characterStyles: [
        { id: 'Hyperlink', name: 'Hyperlink', basedOn: 'DefaultParagraphFont', run: { color: '0563C1', underline: { type: 'single' } } },
      ],
      paragraphStyles: [
        style('Title', 'Title', { run: { font: BODY_FONT, size: 48, bold: true }, paragraph: { spacing: { after: 240 } } }),
        style('Heading1', 'heading 1', heading(36, 360)),
        style('Heading2', 'heading 2', heading(30, 300)),
        style('Heading3', 'heading 3', heading(26, 240)),
        style('Heading4', 'heading 4', heading(24, 200)),
        style('Heading5', 'heading 5', heading(22, 200)),
        style('Heading6', 'heading 6', heading(22, 200)),
        style('Quote', 'Quote', {
          run: { italics: true, color: '555555' },
          paragraph: { indent: { left: 567 }, border: { left: { style: BorderStyle.SINGLE, size: 12, space: 8, color: '999999' } } },
        }),
        style('Bibliography', 'Bibliography', { paragraph: { indent: { left: 540, hanging: 540 }, spacing: { after: 100 } } }),
        style('SourceCode', 'Source Code', {
          run: { font: CODE_FONT, size: 20 },
          paragraph: { spacing: { after: 0, line: 260 }, shading: { type: 'clear', fill: 'F4F4F4' }, indent: { left: 120, right: 120 } },
        }),
      ],
    },
    sections: [{
      properties: {
        page: {
          size: letter
            ? { width: 12240, height: 15840, orientation: PageOrientation.PORTRAIT }
            : { width: 11906, height: 16838, orientation: PageOrientation.PORTRAIT },
          margin: { top: 1418, bottom: 1418, left: 1418, right: 1418 },
        },
      },
      children,
    }],
  });

  return Packer.toBlob(document);
}
