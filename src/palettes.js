// ========================================
// Loomings — colour palettes
// Ten families from Ensigns (ensigns.tiagojacinto.eu), the author's colour
// system: each named for a ship in Moby-Dick, each with a light and a dark
// mode, each tested for one place of use. Every value here is an Ensigns
// role, mapped once:
//
//   bg          <- roles.bg                bgElev     <- roles.surface-raised
//   bgDeep      <- roles.surface           fg         <- roles.text
//   fgDim       <- roles.text-muted        fgGhost    <- roles.text-subtle
//   accent      <- roles.accent            accentLight<- roles.link
//   accentDim   <- roles.text-subtle       border     <- roles.border
//   selection   <- roles.selection         onAccent   <- roles.on-accent
//
// Headings, emphasis and code take ink (an Ensigns family marks interaction
// with colour, not structure); list markers take the accent. When Ensigns
// omits a role for a family (three light modes have no
// surface-raised, one has no on-accent, Delight is monochrome and publishes
// no semantic roles at all) the nearest published role is used, or ink is
// chosen by contrast against the accent. One published pair, Enderby's
// light on-accent (4.09:1 on brass), sits below AA for the app's 12px
// labels, so black is used there for the same reason. Five light-mode
// selections (Jeroboam, Townho, Rosebud, Bachelor, Rachel) are high-chroma flags at
// ~1.05:1 against their page — fine as a browser highlight, invisible as a
// drawn editor block — so each is deepened 10% toward the family's ink,
// which keeps the hue and reaches ~1.29:1. The test holds that floor.
// ========================================

// Keys every mode must define. `heading`, `emphasis`, `code` and `marker`
// are the ink roles for in-place Markdown rendering. They default to ink,
// not to the accent: in Ensigns, colour marks interaction, and a heading is
// structure. A family may override them if its own rules say otherwise.
export const PALETTE_KEYS = [
  'bg', 'bgElev', 'bgDeep', 'fg', 'fgDim', 'fgGhost',
  'accent', 'accentLight', 'accentDim', 'border',
  'selection', 'onAccent',
];

export const PALETTES = {
  pequod: {
    label: 'Pequod',
    modes: { dark: 'Below deck', light: 'Parchment' },
    dark: {
      bg:           '#0b1720',
      bgElev:       '#0c222f',
      bgDeep:       '#0d2f42',
      fg:           '#eae1d7',
      fgDim:        '#bfbbb6',
      fgGhost:      '#a16e50',
      accent:       '#bd8c68',
      accentLight:  '#9dc2c5',
      accentDim:    '#a16e50',
      border:       '#163f54',
      selection:    '#0d2f42',
      onAccent:     '#0b1720',
    },
    light: {
      bg:           '#eae1d7',
      bgElev:       '#f7f3ee',
      bgDeep:       '#dbc9b6',
      fg:           '#0d2f42',
      fgDim:        '#335260',
      fgGhost:      '#835a49',
      accent:       '#163f54',
      accentLight:  '#163f54',
      accentDim:    '#835a49',
      border:       '#cfad8e',
      selection:    '#dbc9b6',
      onAccent:     '#eae1d7',
    },
  },

  goney: {
    label: 'Goney',
    modes: { dark: 'Profundum', light: 'Pruina' },
    dark: {
      bg:           '#10161c',
      bgElev:       '#1f2932',
      bgDeep:       '#171f26',
      fg:           '#e8eef2',
      fgDim:        '#8c8c8c',
      fgGhost:      '#8c8c8c',
      accent:       '#3d97ff',
      accentLight:  '#3d97ff',
      accentDim:    '#8c8c8c',
      border:       '#2a3540',
      selection:    '#2b4356',
      onAccent:     '#0b1218',
    },
    light: {
      bg:           '#f0f4f6',
      bgElev:       '#f7fafb',
      bgDeep:       '#f7fafb',
      fg:           '#16222a',
      fgDim:        '#55646d',
      fgGhost:      '#55646d',
      accent:       '#0b62cf',
      accentLight:  '#0b62cf',
      accentDim:    '#55646d',
      border:       '#cdd7dc',
      selection:    '#b7cdd6',
      onAccent:     '#f2f7fb',
    },
  },

  townho: {
    label: 'Townho',
    modes: { dark: 'Golden Inn night', light: 'Golden Inn daylight' },
    dark: {
      bg:           '#161310',
      bgElev:       '#2b241f',
      bgDeep:       '#201b17',
      fg:           '#f2ece2',
      fgDim:        '#c0b6a8',
      fgGhost:      '#8c8174',
      accent:       '#8fbeff',
      accentLight:  '#8fbeff',
      accentDim:    '#8c8174',
      border:       '#3e352c',
      selection:    '#4f4200',
      onAccent:     '#161310',
    },
    light: {
      bg:           '#f6f2e9',
      bgElev:       '#e2dacb',
      bgDeep:       '#ede7da',
      fg:           '#151210',
      fgDim:        '#4e473d',
      fgGhost:      '#70685c',
      accent:       '#003a95',
      accentLight:  '#003a95',
      accentDim:    '#70685c',
      border:       '#d8cfbe',
      selection:    '#e1dd33',
      onAccent:     '#f6f2e9',
    },
  },

  jeroboam: {
    label: 'Jeroboam',
    modes: { dark: 'Dark', light: 'Light' },
    dark: {
      bg:           '#1a1713',
      bgElev:       '#292521',
      bgDeep:       '#211d19',
      fg:           '#f1edea',
      fgDim:        '#c5c1bb',
      fgGhost:      '#b2aea8',
      accent:       '#b3aebf',
      accentLight:  '#d4d0e1',
      accentDim:    '#b2aea8',
      border:       '#383430',
      selection:    '#3c3934',
      onAccent:     '#1a1713',
    },
    light: {
      bg:           '#f6f3f0',
      bgElev:       '#fcf9f5',
      bgDeep:       '#fcf9f5',
      fg:           '#1e1b17',
      fgDim:        '#4c4844',
      fgGhost:      '#534f4b',
      accent:       '#2e2a38',
      accentLight:  '#423e4c',
      accentDim:    '#534f4b',
      border:       '#d5d1cb',
      selection:    '#d2cec9',
      onAccent:     '#fcf9f5',
    },
  },

  jungfrau: {
    label: 'Jungfrau',
    modes: { dark: 'Try-Fire', light: 'Lamp-feeder' },
    dark: {
      bg:           '#171b21',
      bgElev:       '#242b32',
      bgDeep:       '#1d242a',
      fg:           '#afaca2',
      fgDim:        '#878f93',
      fgGhost:      '#878f93',
      accent:       '#d56f2b',
      accentLight:  '#d56f2b',
      accentDim:    '#878f93',
      border:       '#2e3741',
      selection:    '#2c4953',
      onAccent:     '#171b21',
    },
    light: {
      bg:           '#b5a892',
      bgElev:       '#bcb09c',
      bgDeep:       '#baad97',
      fg:           '#16100a',
      fgDim:        '#3c342a',
      fgGhost:      '#3c342a',
      accent:       '#602500',
      accentLight:  '#602500',
      accentDim:    '#3c342a',
      border:       '#a59986',
      selection:    '#678b8a',
      onAccent:     '#b2a895',
    },
  },

  rosebud: {
    label: 'Rosebud',
    modes: { dark: 'Dark', light: 'Light' },
    dark: {
      bg:           '#1a1f26',
      bgElev:       '#2b3037',
      bgDeep:       '#0c1117',
      fg:           '#eaedef',
      fgDim:        '#aeb2b7',
      fgGhost:      '#8d9298',
      accent:       '#2f9f99',
      accentLight:  '#5bb6b1',
      accentDim:    '#8d9298',
      border:       '#42484e',
      selection:    '#0e3937',
      onAccent:     '#1a1f26',
    },
    light: {
      bg:           '#fafbfd',
      bgElev:       '#fafbfd',
      bgDeep:       '#eaedef',
      fg:           '#1a1f26',
      fgDim:        '#5c6168',
      fgGhost:      '#72777d',
      accent:       '#2f9f99',
      accentLight:  '#1e807b',
      accentDim:    '#72777d',
      border:       '#c8cbd0',
      selection:    '#d3e2e1',
      onAccent:     '#1a1f26',
    },
  },

  enderby: {
    label: 'Enderby',
    modes: { dark: 'Pilot-cloth', light: 'Ivory' },
    dark: {
      bg:           '#0e1824',
      bgElev:       '#202b39',
      bgDeep:       '#17212f',
      fg:           '#ece8d9',
      fgDim:        '#b8b4a6',
      fgGhost:      '#ada99c',
      accent:       '#d8b456',
      accentLight:  '#7fbef4',
      accentDim:    '#ada99c',
      border:       '#333e4d',
      selection:    '#233f5b',
      onAccent:     '#0e1824',
    },
    light: {
      bg:           '#faf7ee',
      bgElev:       '#fefcf8',
      bgDeep:       '#f3f0e7',
      fg:           '#1e2736',
      fgDim:        '#3f4857',
      fgGhost:      '#47505e',
      accent:       '#a38122',
      accentLight:  '#0c4694',
      accentDim:    '#47505e',
      border:       '#d7d4ca',
      selection:    '#cae3fd',
      onAccent:     '#000000',
    },
  },

  bachelor: {
    label: 'Bachelor',
    modes: { dark: 'Brazen lamp', light: 'Holiday apparel' },
    dark: {
      bg:           '#080e1c',
      bgElev:       '#1f2636',
      bgDeep:       '#151b2a',
      fg:           '#f7f4ec',
      fgDim:        '#cdc8be',
      fgGhost:      '#a5a29a',
      accent:       '#fff000',
      accentLight:  '#fff000',
      accentDim:    '#a5a29a',
      border:       '#677081',
      selection:    '#0000c9',
      onAccent:     '#100d01',
    },
    light: {
      bg:           '#f3f0e9',
      bgElev:       '#ebe7de',
      bgDeep:       '#ebe7de',
      fg:           '#0b111f',
      fgDim:        '#3f4450',
      fgGhost:      '#6b7079',
      accent:       '#0000c9',
      accentLight:  '#0000c9',
      accentDim:    '#6b7079',
      border:       '#84817a',
      selection:    '#e7da03',
      onAccent:     '#ffffff',
    },
  },

  rachel: {
    label: 'Rachel',
    modes: { dark: 'Beacon', light: 'Daylight' },
    dark: {
      bg:           '#1f1813',
      bgElev:       '#2e2620',
      bgDeep:       '#261f19',
      fg:           '#f1e7d2',
      fgDim:        '#d7cbb7',
      fgGhost:      '#d7cbb7',
      accent:       '#9dd1ff',
      accentLight:  '#9dd1ff',
      accentDim:    '#d7cbb7',
      border:       '#897965',
      selection:    '#1f405e',
      onAccent:     '#1f1813',
    },
    light: {
      bg:           '#f7efe0',
      bgElev:       '#fdfaf1',
      bgDeep:       '#f3e8d5',
      fg:           '#20160e',
      fgDim:        '#4c3b30',
      fgGhost:      '#4c3b30',
      accent:       '#034574',
      accentLight:  '#034574',
      accentDim:    '#4c3b30',
      border:       '#887865',
      selection:    '#c7d7e5',
      onAccent:     '#f7efe0',
    },
  },

  delight: {
    label: 'Delight',
    modes: { dark: 'Sad burial', light: 'White ribs' },
    dark: {
      bg:           '#111111',
      bgElev:       '#1a1a1a',
      bgDeep:       '#222222',
      fg:           '#eeeeee',
      fgDim:        '#bbbbbb',
      fgGhost:      '#888888',
      accent:       '#ffffff',
      accentLight:  '#ffffff',
      accentDim:    '#888888',
      border:       '#555555',
      selection:    '#333333',
      onAccent:     '#111111',
    },
    light: {
      bg:           '#ffffff',
      bgElev:       '#ffffff',
      bgDeep:       '#eeeeee',
      fg:           '#000000',
      fgDim:        '#333333',
      fgGhost:      '#555555',
      accent:       '#000000',
      accentLight:  '#000000',
      accentDim:    '#555555',
      border:       '#bbbbbb',
      selection:    '#dddddd',
      onAccent:     '#ffffff',
    },
  },
};

export const FAMILY_ORDER = ['pequod', 'goney', 'townho', 'jeroboam', 'jungfrau', 'rosebud', 'enderby', 'bachelor', 'rachel', 'delight'];
export const DEFAULT_FAMILY = 'pequod';

// A mode's colours plus the resolved ink roles.
export function roles(family, mode) {
  const p = PALETTES[family][mode];
  return {
    ...p,
    heading:  p.heading  || p.fg,
    emphasis: p.emphasis || p.fg,
    code:     p.code     || p.fgDim,
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
    '--border': r.border, '--selection': r.selection, '--on-accent': r.onAccent,
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
