/**
 * GoDrive Admin - Design System Tokens
 * Single source of truth for all design decisions.
 * Brand green extracted from GODRIVE.png logo (#80B445 family).
 */

export const colors = {
  // Base neutrals
  neutral: {
    0: '#ffffff',
    50: '#f8fafc',
    100: '#f1f5f9',
    200: '#e2e8f0',
    300: '#cbd5e1',
    400: '#94a3b8',
    500: '#64748b',
    600: '#475569',
    700: '#334155',
    800: '#1e293b',
    900: '#0f172a',
    950: '#020617',
  },

  // Brand colors — GoDrive logo green & charcoal slate
  brand: {
    primary: {
      50: '#f3f9ec',
      100: '#e2f2d3',
      200: '#c5e5a6',
      300: '#a2d473',
      400: '#83c345',
      500: '#6bb522',  // exact GoDrive logo green
      600: '#579619',  // hover
      700: '#457715',  // pressed
      800: '#385f14',
      900: '#2f4f13',
      950: '#172c08',
    },
    charcoal: {
      50: '#f7f8f9',
      100: '#edf0f2',
      200: '#dbe0e5',
      300: '#b7c1cb',
      400: '#8997a5',
      500: '#53585f',  // logo "Go" Charcoal
      600: '#42474e',
      700: '#32363c',
      800: '#23272c',
      900: '#14171a',
    },
  },

  // Semantic colors
  semantic: {
    success: {
      light: '#f3f9ec',
      main: '#6bb522',
      dark: '#457715',
      contrastText: '#ffffff',
    },
    warning: {
      light: '#fef3c7',
      main: '#f59e0b',
      dark: '#92400e',
      contrastText: '#ffffff',
    },
    error: {
      light: '#fee2e2',
      main: '#ef4444',
      dark: '#991b1b',
      contrastText: '#ffffff',
    },
    info: {
      light: '#f3f9ec',
      main: '#6bb522',
      dark: '#457715',
      contrastText: '#ffffff',
    },
  },

  // Dark mode surfaces (GoDrive Slate theme)
  dark: {
    bg: {
      primary: '#0d1117',
      secondary: '#161b22',
      tertiary: '#21262d',
      elevated: '#21262d',
      overlay: 'rgba(13, 17, 23, 0.8)',
    },
    surface: {
      primary: '#161b22',
      secondary: '#21262d',
      tertiary: '#30363d',
      hover: '#30363d',
      active: '#3c434c',
    },
    border: {
      primary: '#30363d',
      secondary: '#3c434c',
      focus: '#6bb522',
      error: '#ef4444',
    },
    text: {
      primary: '#f0f6fc',
      secondary: '#c6d0db',
      tertiary: '#8b949e',
      inverse: '#0d1117',
      disabled: '#6e7681',
      link: '#6bb522',
    },
  },
};

export const typography = {
  fontFamilies: {
    sans: '"IBM Plex Sans Arabic", "Inter", system-ui, -apple-system, sans-serif',
    mono: '"JetBrains Mono", "Fira Code", monospace',
  },
  fontWeights: {
    light: 300,
    regular: 400,
    medium: 500,
    semibold: 600,
    bold: 700,
  },
  fontSizes: {
    xs: '0.7rem',      // 11.2px
    sm: '0.78rem',     // 12.48px
    base: '0.875rem',  // 14px
    md: '0.95rem',     // 15.2px
    lg: '1.05rem',     // 16.8px
    xl: '1.25rem',     // 20px
    '2xl': '1.5rem',   // 24px
    '3xl': '1.875rem', // 30px
    '4xl': '2.25rem',  // 36px
  },
  lineHeights: {
    tight: 1.2,
    normal: 1.5,
    relaxed: 1.6,
  },
  letterSpacing: {
    tight: '-0.02em',
    normal: '0',
    wide: '0.02em',
  },
};

export const spacing = {
  base: 4, // 4px base unit
  scale: {
    0: 0,
    1: 4,
    2: 8,
    3: 12,
    4: 16,
    5: 20,
    6: 24,
    8: 32,
    10: 40,
    12: 48,
    16: 64,
    20: 80,
  },
};

export const borderRadius = {
  none: 0,
  sm: '4px',
  md: '8px',
  lg: '12px',
  xl: '16px',
  '2xl': '20px',
  full: '9999px',
};

export const shadows = {
  none: 'none',
  xs: '0 1px 2px rgba(0, 0, 0, 0.05)',
  sm: '0 1px 3px rgba(0, 0, 0, 0.1), 0 1px 2px rgba(0, 0, 0, 0.06)',
  md: '0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)',
  lg: '0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)',
  xl: '0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04)',
  '2xl': '0 25px 50px -12px rgba(0, 0, 0, 0.25)',
  inner: 'inset 0 2px 4px rgba(0, 0, 0, 0.06)',
  focus: '0 0 0 3px rgba(59, 130, 246, 0.4)',
};

export const transitions = {
  fast: '150ms ease',
  normal: '200ms ease',
  slow: '300ms ease',
};

export const zIndex = {
  hide: -1,
  base: 0,
  dropdown: 1000,
  sticky: 1100,
  fixed: 1200,
  modalBackdrop: 1300,
  modal: 1400,
  popover: 1500,
  tooltip: 1600,
  toast: 1700,
};

export const breakpoints = {
  sm: '640px',
  md: '768px',
  lg: '1024px',
  xl: '1280px',
  '2xl': '1536px',
};

export const container = {
  maxWidth: '1440px',
  padding: '24px',
};

export const layout = {
  sidebar: {
    width: '260px',
    collapsedWidth: '72px',
    headerHeight: '64px',
  },
  header: {
    height: '64px',
  },
  content: {
    maxWidth: '1440px',
    padding: '24px',
  },
};

export const designTokens = {
  colors,
  typography,
  spacing,
  borderRadius,
  shadows,
  transitions,
  zIndex,
  breakpoints,
  container,
  layout,
};

export type DesignTokens = typeof designTokens;