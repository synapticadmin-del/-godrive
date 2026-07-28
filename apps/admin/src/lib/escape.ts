/**
 * Escape a value for safe interpolation into an HTML string.
 *
 * Map popups and div icons are built with template strings and injected via
 * `L.divIcon({ html })` / `bindPopup(...)`, which does NOT sanitize. Any
 * dynamic value (names, phones, plates, emails, cities, ids) that contains
 * markup would otherwise execute. Numbers are escaped too for defense in depth.
 */
export function escapeHtml(v: unknown): string {
  return String(v ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
