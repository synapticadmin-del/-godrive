import React from 'react';

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  variant?: 'default' | 'success' | 'warning' | 'danger' | 'info' | 'neutral';
  size?: 'sm' | 'md' | 'lg';
  dot?: boolean;
}

export const Badge = React.forwardRef<HTMLSpanElement, BadgeProps>(
  ({ children, variant = 'neutral', size = 'md', dot = false, className = '', ...props }, ref) => {
    const variantStyles = {
      default: 'bg-surface-tertiary text-text-secondary border border-border-primary',
      success: 'bg-success-light text-success-main border border-success-main/30',
      warning: 'bg-warning-light text-warning-main border border-warning-main/30',
      danger: 'bg-error-light text-error-main border border-error-main/30',
      info: 'bg-info-light text-info-main border border-info-main/30',
      neutral: 'bg-surface-tertiary text-text-secondary border border-border-primary',
    };

    const sizeStyles = {
      sm: 'px-2 py-0.5 text-[11px] gap-1 font-bold',
      md: 'px-2.5 py-0.5 text-xs gap-1.5 font-bold',
      lg: 'px-3 py-1 text-sm gap-2 font-bold',
    };

    return (
      <span
        ref={ref}
        className={`
          inline-flex items-center font-bold rounded-full
          ${variantStyles[variant]}
          ${sizeStyles[size]}
          ${className}
        `}
        {...props}
      >
        {dot && (
          <span
            className="w-1.5 h-1.5 rounded-full bg-current opacity-90"
            aria-hidden="true"
          />
        )}
        {children}
      </span>
    );
  },
);

Badge.displayName = 'Badge';

export const StatusBadge = ({ status, className = '' }: { status: string; className?: string }) => {
  const statusConfig: Record<string, { label: string; variant: BadgeProps['variant']; dot: boolean }> = {
    active: { label: 'نشط', variant: 'success', dot: true },
    inactive: { label: 'غير نشط', variant: 'neutral', dot: false },
    pending: { label: 'بانتظار الموافقة', variant: 'warning', dot: false },
    approved: { label: 'معتمد', variant: 'success', dot: false },
    rejected: { label: 'مرفوض', variant: 'danger', dot: false },
    suspended: { label: 'موقوف', variant: 'danger', dot: false },
    searching: { label: 'جاري البحث', variant: 'info', dot: true },
    offered: { label: 'قيد العرض', variant: 'warning', dot: true },
    assigned: { label: 'مُعين', variant: 'info', dot: true },
    arrived: { label: 'وصل الكابتن', variant: 'info', dot: true },
    in_progress: { label: 'قيد التنفيذ', variant: 'info', dot: true },
    completed: { label: 'مكتملة', variant: 'success', dot: false },
    cancelled: { label: 'ملغية', variant: 'danger', dot: false },
    online: { label: 'متصل', variant: 'success', dot: true },
    offline: { label: 'غير متصل', variant: 'neutral', dot: false },
  };

  const config = statusConfig[status] || { label: status, variant: 'neutral', dot: false };

  return (
    <Badge variant={config.variant} dot={config.dot} className={className}>
      {config.label}
    </Badge>
  );
};