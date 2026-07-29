import React from 'react';

/**
 * Shared pagination footer.
 *
 * Extracted from DataTable so that pages which are NOT tables (e.g. the captain
 * verification accordion) get the exact same paging affordance instead of
 * silently rendering every row with no way to advance.
 *
 * Works for both client-side paging (DataTable slices an in-memory array) and
 * server-side paging (the caller refetches on `onPageChange`).
 *
 * `page` is 1-based.
 *
 * Arrow direction follows the RTL convention already used elsewhere in the
 * admin app: "previous" points right, "next" points left.
 */
export interface PaginationProps {
  /** 1-based index of the page currently shown. */
  page: number;
  /** Total number of pages. Always >= 1. */
  totalPages: number;
  onPageChange: (page: number) => void;
  /** Total records across all pages, shown as a hint next to the page counter. */
  totalItems?: number;
  /** Noun for a single record — "12 كابتن" vs "12 نتيجة". */
  itemNoun?: string;
  pageSize?: number;
  pageSizeOptions?: number[];
  onPageSizeChange?: (size: number) => void;
  /** Greys out the arrows while a request is in flight (server-side paging). */
  busy?: boolean;
  className?: string;
}

function ChevronRightIcon() {
  return (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
    </svg>
  );
}

function ChevronLeftIcon() {
  return (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
    </svg>
  );
}

export function Pagination({
  page,
  totalPages,
  onPageChange,
  totalItems,
  itemNoun = 'نتيجة',
  pageSize,
  pageSizeOptions,
  onPageSizeChange,
  busy = false,
  className = '',
}: PaginationProps) {
  const safeTotalPages = Math.max(totalPages, 1);
  const isFirst = page <= 1;
  const isLast = page >= safeTotalPages;

  // Keep the size picker optional: server-paged callers may not offer one.
  const sizePicker =
    typeof pageSize === 'number' && onPageSizeChange && pageSizeOptions && pageSizeOptions.length > 0 ? (
      <div className="flex items-center gap-2 text-sm text-text-secondary">
        <span>عرض</span>
        <select
          value={pageSize}
          onChange={(e) => onPageSizeChange(Number(e.target.value))}
          className="px-2 py-1 bg-surface-secondary border border-border-primary rounded-lg text-text-primary focus:border-focus focus:outline-none focus:ring-2 focus:ring-primary-500/20"
        >
          {pageSizeOptions.map((size) => (
            <option key={size} value={size}>
              {size}
            </option>
          ))}
        </select>
        <span>في الصفحة</span>
      </div>
    ) : (
      <span />
    );

  return (
    <div
      className={`px-4 py-3 border-t border-border-primary flex flex-col sm:flex-row items-center justify-between gap-3 ${className}`}
    >
      {sizePicker}

      <div className="flex items-center gap-2">
        <span className="text-sm text-text-secondary">
          صفحة {page} من {safeTotalPages}
          {typeof totalItems === 'number' ? ` (${totalItems} ${itemNoun})` : ''}
        </span>
        <button
          onClick={() => onPageChange(page - 1)}
          disabled={isFirst || busy}
          className="p-2 rounded-lg hover:bg-surface-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          aria-label="الصفحة السابقة"
          title="الصفحة السابقة"
        >
          <ChevronRightIcon />
        </button>
        <button
          onClick={() => onPageChange(page + 1)}
          disabled={isLast || busy}
          className="p-2 rounded-lg hover:bg-surface-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          aria-label="الصفحة التالية"
          title="الصفحة التالية"
        >
          <ChevronLeftIcon />
        </button>
      </div>
    </div>
  );
}

export default Pagination;
