/** @type {import('tailwindcss').Config} */
/**
 * Dual-theme design system: semantic color groups (bg/surface/border/text)
 * resolve through CSS variables defined in styles.css for :root (light/white)
 * and .dark (pure black). Using rgb(var(--x) / <alpha-value>) keeps Tailwind
 * opacity modifiers (e.g. bg-surface-primary/80) working in both themes.
 */
const v = (name) => `rgb(var(${name}) / <alpha-value>)`;

export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        bg: {
          primary: v("--bg-primary"),
          secondary: v("--bg-secondary"),
          tertiary: v("--bg-tertiary"),
          elevated: v("--bg-elevated"),
          overlay: "rgba(0, 0, 0, 0.55)",
        },
        surface: {
          primary: v("--surface-primary"),
          secondary: v("--surface-secondary"),
          tertiary: v("--surface-tertiary"),
          hover: v("--surface-hover"),
          active: v("--surface-active"),
        },
        border: {
          primary: v("--border-primary"),
          secondary: v("--border-secondary"),
          focus: "#1472ed",
          error: "#ef4444",
        },
        text: {
          primary: v("--text-primary"),
          secondary: v("--text-secondary"),
          tertiary: v("--text-tertiary"),
          inverse: v("--text-inverse"),
          disabled: v("--text-disabled"),
          link: "#0c5ac0",
        },
        primary: {
          50: "#f4f7fc",
          100: "#e5eef9",
          200: "#caddf6",
          300: "#a9c8f1",
          400: "#87b4f0",
          500: "#1472ed", // Tempo Blue
          600: "#0c5ac0",
          700: "#0a489a",
          800: "#063879",
          900: "#052958",
          950: "#031935",
        },
        brandCharcoal: {
          50: "#f7f8f9",
          100: "#edf0f2",
          200: "#dbe0e5",
          300: "#b7c1cb",
          400: "#8997a5",
          500: "#53585f", // Logo "Go" Charcoal
          600: "#42474e",
          700: "#32363c",
          800: "#23272c",
          900: "#14171a",
          950: "#0b0d0e",
        },
        success: {
          light: v("--success-light"),
          main: "#6bb522",
          dark: "#457715",
        },
        warning: {
          light: v("--warning-light"),
          main: "#f59e0b",
          dark: "#92400e",
        },
        error: {
          light: v("--error-light"),
          main: "#ef4444",
          dark: "#991b1b",
        },
        info: {
          light: v("--info-light"),
          main: "#6bb522",
          dark: "#457715",
        },
      },
      fontFamily: {
        sans: ['"IBM Plex Sans Arabic"', "system-ui", "sans-serif"],
        mono: ['"JetBrains Mono"', "monospace"],
      },
      borderRadius: {
        sm: "4px",
        md: "8px",
        lg: "12px",
        xl: "16px",
        "2xl": "20px",
      },
      boxShadow: {
        xs: "0 1px 2px rgba(0, 0, 0, 0.05)",
        sm: "0 1px 3px rgba(0, 0, 0, 0.1), 0 1px 2px rgba(0, 0, 0, 0.06)",
        md: "0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)",
        lg: "0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)",
        xl: "0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04)",
        "2xl": "0 25px 50px -12px rgba(0, 0, 0, 0.25)",
      },
      animation: {
        "fade-in": "fadeIn 0.2s ease-out",
        "slide-up": "slideInUp 0.3s ease-out",
        "slide-down": "slideInDown 0.3s ease-out",
      },
      keyframes: {
        fadeIn: {
          "0%": { opacity: "0" },
          "100%": { opacity: "1" },
        },
        slideInUp: {
          "0%": { opacity: "0", transform: "translateY(8px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
        slideInDown: {
          "0%": { opacity: "0", transform: "translateY(-8px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
      },
    },
  },
  plugins: [],
};