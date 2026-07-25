import React, { useState, useMemo, forwardRef } from 'react';

export interface Column<T> {
  key: string;
  header: string;
  accessor: (row: T) => React.ReactNode;
  sortable?: boolean;
  width?: string;
  align?: 'left' | 'center' | 'right';
  render?: (value: any, row: T) => React.ReactNode;
}

export interface DataTableProps<T> {
  data: T[];
  columns: Column<T>[];
  keyAccessor: (row: T) => string;
  sortable?: boolean;
  defaultSortKey?: string;
  defaultSortDirection?: 'asc' | 'desc';
  pagination?: boolean;
  pageSize?: number;
  pageSizeOptions?: number[];
  loading?: boolean;
  emptyMessage?: string;
  onRowClick?: (row: T) => void;
  rowActions?: {
    label: string;
    icon?: React.ReactNode;
    onClick: (row: T) => void;
    variant?: 'default' | 'danger';
    disabled?: (row: T) => boolean;
    show?: (row: T) => boolean;
  }[];
  striped?: boolean;
  hoverable?: boolean;
  className?: string;
}

function ChevronUp({ className = '' }: { className?: string }) {
  return (
    <svg className={`w-4 h-4 ${className}`} fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 15l7-7 7 7" />
    </svg>
  );
}

function ChevronDown({ className = '' }: { className?: string }) {
  return (
    <svg className={`w-4 h-4 ${className}`} fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
    </svg>
  );
}

function Minus({ className = '' }: { className?: string }) {
  return (
    <svg className={`w-4 h-4 ${className}`} fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 12h14" />
    </svg>
  );
}

export function DataTable<T extends Record<string, any>>({
  data,
  columns,
  keyAccessor,
  sortable = true,
  defaultSortKey,
  defaultSortDirection = 'asc',
  pagination = true,
  pageSize: initialPageSize = 10,
  pageSizeOptions = [10, 25, 50, 100],
  loading = false,
  emptyMessage = 'لا توجد بيانات',
  onRowClick,
  rowActions = [],
  striped = true,
  hoverable = true,
  className = '',
}: DataTableProps<T>) {
  const [sortKey, setSortKey] = useState<string | null>(defaultSortKey || null);
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>(defaultSortDirection);
  const [page, setPage] = useState(0);
  const [pageSize, setPageSize] = useState(initialPageSize);

  const sortedData = useMemo(() => {
    if (!sortKey || !sortable) return data;
    return [...data].sort((a, b) => {
      const column = columns.find((c) => c.key === sortKey);
      if (!column?.sortable) return 0;
      const aVal = a[sortKey];
      const bVal = b[sortKey];
      if (aVal === bVal) return 0;
      const comparison = aVal < bVal ? -1 : 1;
      return sortDirection === 'asc' ? comparison : -comparison;
    });
  }, [data, sortKey, sortDirection, sortable, columns]);

  const paginatedData = useMemo(() => {
    if (!pagination) return sortedData;
    const start = page * pageSize;
    return sortedData.slice(start, start + pageSize);
  }, [sortedData, pagination, page, pageSize]);

  const totalPages = Math.ceil(sortedData.length / pageSize) || 1;

  const handleSort = (key: string) => {
    if (!sortable) return;
    const column = columns.find((c) => c.key === key);
    if (!column?.sortable) return;
    if (sortKey === key) {
      setSortDirection((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(key);
      setSortDirection('asc');
    }
    setPage(0);
  };

  const handlePageChange = (newPage: number) => {
    setPage(Math.max(0, Math.min(newPage, totalPages - 1)));
  };

  const handlePageSizeChange = (newSize: number) => {
    setPageSize(newSize);
    setPage(0);
  };

  if (loading) {
    return (
      <div className="overflow-x-auto">
        <div className="bg-surface-primary border border-border-primary rounded-xl">
          <div className="overflow-x-auto">
            <table className="w-full" role="table">
              <thead>
                <tr className="border-b border-border-primary">
                  {columns.map((col) => (
                    <th
                      key={col.key}
                      className="px-4 py-3 text-right text-sm font-medium text-text-secondary"
                      style={{ width: col.width ?? undefined }}
                    >
                      {col.header}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {[...Array(5)].map((_, i) => (
                  <tr key={i} className="border-b border-border-primary/50">
                    {columns.map((col) => (
                      <td key={col.key} className="px-4 py-3">
                        <div className="h-4 bg-surface-tertiary animate-pulse rounded w-3/4" />
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    );
  }

  if (data.length === 0) {
    return (
      <div className="bg-surface-primary border border-border-primary rounded-xl p-12 text-center">
        <svg className="w-12 h-12 mx-auto text-text-tertiary mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
        </svg>
        <p className="text-text-secondary text-lg">{emptyMessage}</p>
      </div>
    );
  }

  return (
    <div className={`overflow-x-auto ${className}`}>
      <div className="bg-surface-primary border border-border-primary rounded-xl overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full" role="table">
            <thead>
              <tr className="border-b border-border-primary bg-surface-secondary/50">
                {columns.map((col) => (
                  <th
                    key={col.key}
                    className={`px-4 py-3 text-sm font-semibold text-text-secondary ${col.align === 'center' ? 'text-center' : col.align === 'left' ? 'text-left' : 'text-right'} relative`}
                    style={{ width: col.width ?? undefined }}
                    scope="col"
                  >
                    <div className="flex items-center gap-2 justify-end">
                      <span>{col.header}</span>
                      {col.sortable && sortable && (
                        <button
                          onClick={() => handleSort(col.key)}
                          className="p-1 rounded hover:bg-surface-hover transition-colors text-text-tertiary hover:text-text-primary focus:outline-none focus:ring-2 focus:ring-primary-500/40"
                          aria-sort={sortKey === col.key ? (sortDirection === 'asc' ? 'ascending' : 'descending') : 'none'}
                          aria-label={`فرز حسب ${col.header}`}
                        >
                          {sortKey === col.key ? (
                            sortDirection === 'asc' ? <ChevronUp className="w-4 h-4 text-primary-500" /> : <ChevronDown className="w-4 h-4 text-primary-500" />
                          ) : (
                            <Minus className="w-4 h-4 text-text-tertiary" />
                          )}
                        </button>
                      )}
                    </div>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-border-primary/50">
              {paginatedData.map((row, rowIndex) => {
                const isStriped = striped && rowIndex % 2 === 1;
                const isHoverable = hoverable;

                return (
                  <tr
                    key={keyAccessor(row)}
                    className={`
                      transition-colors duration-100
                      ${isStriped ? 'bg-surface-secondary/30' : ''}
                      ${isHoverable ? 'hover:bg-surface-hover' : ''}
                      ${onRowClick ? 'cursor-pointer' : ''}
                    `}
                    onClick={() => onRowClick?.(row)}
                    onKeyDown={(e) => {
                      if ((e.key === 'Enter' || e.key === ' ') && onRowClick) {
                        e.preventDefault();
                        onRowClick(row);
                      }
                    }}
                    tabIndex={onRowClick ? 0 : undefined}
                  >
                    {columns.map((col) => (
                      <td
                        key={col.key}
                        className={`px-4 py-3 ${col.align === 'center' ? 'text-center' : col.align === 'left' ? 'text-left' : 'text-right'}`}
                        style={{ width: col.width ?? undefined }}
                      >
                        {col.render ? col.render(row[col.key as keyof T], row) : col.accessor(row)}
                      </td>
                    ))}
                    {rowActions.length > 0 && (
                      <td className="px-4 py-3 text-left">
                        <div className="flex items-center gap-1 justify-end">
                          {rowActions
                            .filter((action) => !action.show || action.show(row))
                            .map((action, i) => (
                              <button
                                key={i}
                                onClick={(e) => {
                                  e.stopPropagation();
                                  action.onClick(row);
                                }}
                                disabled={action.disabled?.(row)}
                                className={`
                                  p-1.5 rounded-lg transition-colors
                                  ${action.variant === 'danger'
                                    ? 'text-error-main hover:bg-error-light'
                                    : 'text-text-tertiary hover:bg-surface-hover hover:text-text-primary'}
                                  disabled:opacity-50 disabled:cursor-not-allowed
                                `}
                                aria-label={action.label}
                              >
                                {action.icon || (
                                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                                  </svg>
                                )}
                              </button>
                            ))}
                        </div>
                      </td>
                    )}
                  </tr>
                );
              })}
              {paginatedData.length < (pagination ? pageSize : data.length) && (
                <tr>
                  <td colSpan={columns.length + (rowActions.length > 0 ? 1 : 0)} className="px-4 py-8 text-center text-text-tertiary">
                    {emptyMessage}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {pagination && totalPages > 1 && (
          <div className="px-4 py-3 border-t border-border-primary flex flex-col sm:flex-row items-center justify-between gap-3">
            <div className="flex items-center gap-2 text-sm text-text-secondary">
              <span>عرض</span>
              <select
                value={pageSize}
                onChange={(e) => handlePageSizeChange(Number(e.target.value))}
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

            <div className="flex items-center gap-2">
              <span className="text-sm text-text-secondary">
                صفحة {page + 1} من {totalPages} ({sortedData.length} نتيجة)
              </span>
              <button
                onClick={() => handlePageChange(page - 1)}
                disabled={page === 0}
                className="p-2 rounded-lg hover:bg-surface-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                aria-label="الصفحة السابقة"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
                </svg>
              </button>
              <button
                onClick={() => handlePageChange(page + 1)}
                disabled={page >= totalPages - 1}
                className="p-2 rounded-lg hover:bg-surface-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                aria-label="الصفحة التالية"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                </svg>
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export default DataTable;