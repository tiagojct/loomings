// ========================================
// Loomings — colour palettes
// Four families, each with a dark and a light mode. Every value here is
// copied from the design system's own token source; the comments name it.
// editor.js turns these into CodeMirror themes and CSS custom properties,
// so this file is the only place a colour lives.
// ========================================

// Keys every mode must define. `heading`, `emphasis`, `code` and `marker`
// are the ink roles for in-place Markdown rendering; they default to
// accentLight (marker: accent) unless a family's rules say otherwise.
export const PALETTE_KEYS = [
  'bg', 'bgElev', 'bgDeep', 'fg', 'fgDim', 'fgGhost',
  'accent', 'accentLight', 'accentDim', 'border',
];

export const PALETTES = {
  // Pequod — github.com/tiagojct/pequod. Warm paper, deep ink, amber.
  // The original Loomings palette and the default.
  pequod: {
    label: 'Pequod',
    modes: { dark: 'Below deck', light: 'Parchment' },
    dark: {
      bg:          '#061826',
      bgElev:      '#0E2D44',
      bgDeep:      '#02101B',
      fg:          '#F7F3EE',
      fgDim:       '#C4BCAE',
      fgGhost:     '#8B8578',
      accent:      '#BD8C68',
      accentLight: '#D4A882',
      accentDim:   '#8B6348',
      border:      '#0E2D44',
    },
    light: {
      bg:          '#F1E7D2',
      bgElev:      '#F8F0DD',
      bgDeep:      '#E2D5B7',
      fg:          '#1A2D3C',
      fgDim:       '#3F5566',
      fgGhost:     '#7A8B9A',
      accent:      '#8B6348',
      accentLight: '#BD8C68',
      accentDim:   '#4F3825',
      border:      '#D7C9A8',
      // The lighter amber reads at 2.4:1 on parchment — headings, emphasis
      // and code take the deeper accent in light mode.
      heading:     '#8B6348',
      emphasis:    '#8B6348',
      code:        '#8B6348',
    },
  },

  // Glauca — github.com/tiagojct/glauca (src/glauca.json). A pale frost
  // field with one vivid sky-blue. Light-first: Pruina is the default
  // there, Profundum the sibling.
  glauca: {
    label: 'Glauca',
    modes: { dark: 'Profundum', light: 'Pruina' },
    dark: {
      bg:          '#10161c',
      bgElev:      '#1f2932',
      bgDeep:      '#0b1218',
      fg:          '#e8eef2',
      fgDim:       '#93b7c9',
      fgGhost:     '#4d7391',
      accent:      '#3d97ff',
      accentLight: '#6cb2ff',
      accentDim:   '#007aff',
      border:      '#2a3540',
    },
    light: {
      bg:          '#f0f4f6',
      bgElev:      '#ffffff',
      bgDeep:      '#e8eef2',
      fg:          '#16222a',
      fgDim:       '#55646d',
      fgGhost:     '#8c8c8c',
      accent:      '#0b62cf',
      accentLight: '#007aff',
      accentDim:   '#084b96',
      border:      '#cdd7dc',
    },
  },

  // Try-Works — github.com/tiagojct/try-works (src/try-works.json). A cold
  // sea is the field, the try-pot fire the one rare mark. Moby-Dick ch. 96.
  tryworks: {
    label: 'Try-Works',
    modes: { dark: 'Try-Fire', light: 'True Lamp' },
    dark: {
      bg:          '#12161b',
      bgElev:      '#232b32',
      bgDeep:      '#11151a',
      fg:          '#f1efe9',
      fgDim:       '#8fb6bd',
      fgGhost:     '#4d7680',
      accent:      '#c9651d',
      accentLight: '#e0832a',
      accentDim:   '#9a4a16',
      border:      '#2c3640',
    },
    light: {
      bg:          '#dee7e4',
      bgElev:      '#f2f7f4',
      bgDeep:      '#b4ccc9',
      fg:          '#18272b',
      fgDim:       '#52646a',
      fgGhost:     '#97a0a4',
      accent:      '#9e5017',
      accentLight: '#b85f1c',
      accentDim:   '#7a3a10',
      border:      '#c4d2cd',
    },
  },

  // Ambergris — github.com/tiagojct/ambergris (tokens.json v0.3.0). A
  // near-monochrome cool grey ramp with one teal accent that marks
  // interaction only. Mapped from its semantic layer: bg=ground,
  // bgElev=surface-raised, bgDeep=surface (dark) / surface-sunken (light),
  // fg=text-primary, fgDim=text-secondary, fgGhost=text-tertiary,
  // accent=link, accentLight=accent-on-surface, accentDim=accent-line,
  // border=rule. Its first rule — accent never decorates — is why headings,
  // emphasis and code are set in ink here rather than in the accent.
  ambergris: {
    label: 'Ambergris',
    modes: { dark: 'Dark', light: 'Light' },
    dark: {
      bg:          '#0C1117',
      bgElev:      '#2B3037',
      bgDeep:      '#1A1F26',
      fg:          '#EAEDEF',
      fgDim:       '#AEB2B7',
      fgGhost:     '#8D9298',
      accent:      '#5BB6B1',
      accentLight: '#86CDC8',
      accentDim:   '#2F9F99',
      border:      '#42484E',
      heading:     '#EAEDEF',
      emphasis:    '#EAEDEF',
      code:        '#AEB2B7',
      marker:      '#8D9298',
    },
    light: {
      bg:          '#F3F5F7',
      bgElev:      '#FAFBFD',
      bgDeep:      '#EAEDEF',
      fg:          '#1A1F26',
      fgDim:       '#5C6168',
      fgGhost:     '#72777D',
      accent:      '#1E807B',
      accentLight: '#1B6864',
      accentDim:   '#2F9F99',
      border:      '#C8CBD0',
      heading:     '#1A1F26',
      emphasis:    '#1A1F26',
      code:        '#5C6168',
      marker:      '#72777D',
    },
  },
};

export const FAMILY_ORDER = ['pequod', 'glauca', 'tryworks', 'ambergris'];
export const DEFAULT_FAMILY = 'pequod';

// A mode's colours plus the resolved ink roles.
export function roles(family, mode) {
  const p = PALETTES[family][mode];
  return {
    ...p,
    heading:  p.heading  || p.accentLight,
    emphasis: p.emphasis || p.accentLight,
    code:     p.code     || p.accentLight,
    marker:   p.marker   || p.accent,
  };
}

// The CSS custom properties style.css reads, as a {name: value} map.
export function cssVars(family, mode) {
  const r = roles(family, mode);
  return {
    '--bg': r.bg, '--bg-elev': r.bgElev, '--bg-deep': r.bgDeep,
    '--fg': r.fg, '--fg-dim': r.fgDim, '--fg-ghost': r.fgGhost,
    '--accent': r.accent, '--accent-light': r.accentLight, '--accent-dim': r.accentDim,
    '--border': r.border,
    '--heading': r.heading, '--emphasis': r.emphasis, '--code': r.code, '--marker': r.marker,
  };
}

// WCAG 2 relative luminance + contrast ratio, used by the tests and by
// nothing at runtime.
export function contrast(hexA, hexB) {
  const lum = (hex) => {
    const n = parseInt(hex.slice(1), 16);
    const ch = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) => {
      const s = c / 255;
      return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
  };
  const [hi, lo] = [lum(hexA), lum(hexB)].sort((a, b) => b - a);
  return (hi + 0.05) / (lo + 0.05);
}
