// csv.ts — CSV export helpers for the admin dashboard.
//
// Two things make CSV export non-trivial here and are handled deliberately:
//
// 1. ARABIC. Excel on Windows decodes a .csv as the system ANSI codepage
//    unless the file opens with a UTF-8 byte-order mark. Without the BOM every
//    Arabic column header and every captain name arrives as mojibake. The BOM
//    is prepended for that reason and must not be "cleaned up".
//
// 2. MACHINE-READABLE VALUES. The UI formats numbers with
//    toLocaleString('ar-EG'), which emits Arabic-Indic digits (٢٠٢٦) and an
//    Arabic decimal separator. Those are correct on screen and useless in a
//    spreadsheet — they do not parse as numbers. Exported values therefore use
//    Latin digits and a plain ISO-style timestamp, independent of display
//    formatting.

/** A column definition for the exporter: a header plus a value extractor. */
export interface CsvColumn<T> {
  header: string;
  value: (row: T) => string | number | null | undefined;
}

/**
 * Escape a single CSV field per RFC 4180.
 *
 * A field is quoted when it contains a comma, a double quote, a CR or an LF,
 * or has leading/trailing whitespace that would otherwise be lost. Embedded
 * double quotes are doubled.
 */
export function escapeCsvField(value: string | number | null | undefined): string {
  if (value == null) return '';
  const s = String(value);
  if (s === '') return '';

  // Excel and Sheets interpret a leading =, +, -, @ (and tab/CR) as the start
  // of a formula. A crafted field like =HYPERLINK(...) or =cmd|... becomes a
  // live formula in the reviewer's spreadsheet. Prefixing a single quote
  // neutralises it while still displaying the original text.
  const needsFormulaGuard = /^[=+\-@\t\r]/.test(s);
  const guarded = needsFormulaGuard ? `'${s}` : s;

  const mustQuote = /[",\r\n]/.test(guarded) || guarded !== guarded.trim();
  if (!mustQuote) return guarded;
  return `"${guarded.replace(/"/g, '""')}"`;
}

/**
 * Format a timestamp as `YYYY-MM-DD HH:MM:SS` in the viewer's local time.
 *
 * The database mixes two encodings — `datetime('now')` writes
 * "2026-07-25 22:00:10" (space separated) while nowIso() writes
 * "2026-07-25T22:00:10.698Z" (ISO with a T). Both are normalised to one
 * spreadsheet-friendly form here.
 *
 * A space-separated value carries no timezone marker. JavaScript parses such a
 * string as LOCAL time, while the API wrote it as UTC — so it is explicitly
 * marked as UTC before parsing, otherwise the exported time silently shifts by
 * the viewer's offset (3 hours in Cairo).
 */
export function formatCsvDate(input: string | null | undefined): string {
  if (!input) return '';
  const raw = String(input).trim();
  if (!raw) return '';

  // "YYYY-MM-DD HH:MM:SS" with no zone -> tag it as UTC, matching how the API
  // stored it. Anything already carrying a T/Z/offset is left alone.
  const spaceForm = /^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})$/.exec(raw);
  const parseable = spaceForm ? `${spaceForm[1]}T${spaceForm[2]}Z` : raw;

  const d = new Date(parseable);
  if (Number.isNaN(d.getTime())) return raw; // unparseable: pass through verbatim

  const p = (n: number) => String(n).padStart(2, '0');
  return (
    `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ` +
    `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
  );
}

/** Format a number with Latin digits so spreadsheets parse it as numeric. */
export function formatCsvNumber(value: number | null | undefined, decimals = 2): string {
  if (value == null || Number.isNaN(Number(value))) return '';
  const n = Number(value);
  return Number.isInteger(n) ? String(n) : n.toFixed(decimals);
}

/** Build the CSV text (without the BOM) for a set of rows. */
export function buildCsv<T>(rows: T[], columns: CsvColumn<T>[]): string {
  const head = columns.map((c) => escapeCsvField(c.header)).join(',');
  const body = rows.map((row) =>
    columns.map((c) => escapeCsvField(c.value(row))).join(','),
  );
  // CRLF is the line ending RFC 4180 specifies and the one Excel expects.
  return [head, ...body].join('\r\n');
}

/**
 * Build and download a CSV file in the browser.
 *
 * Returns the row count so the caller can report it. Filenames get a
 * YYYY-MM-DD stamp so repeated exports do not overwrite each other.
 */
export function downloadCsv<T>(
  filenameBase: string,
  rows: T[],
  columns: CsvColumn<T>[],
): number {
  const csv = buildCsv(rows, columns);

  // U+FEFF: the UTF-8 BOM. Without it Excel mis-decodes every Arabic string.
  const blob = new Blob([`﻿${csv}`], { type: 'text/csv;charset=utf-8;' });

  const stamp = formatCsvDate(new Date().toISOString()).slice(0, 10);
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${filenameBase}-${stamp}.csv`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  // Revoking synchronously can cancel the download in some browsers; defer it.
  setTimeout(() => URL.revokeObjectURL(url), 1000);

  return rows.length;
}
