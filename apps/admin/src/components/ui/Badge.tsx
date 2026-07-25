import React from 'react';

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  variant?: 'default' | 'success' | 'warning' | 'danger' | 'info' | 'neutral';
  size?: 'sm' | 'md' | 'lg';
  dot?: boolean;
}

export const Badge = React.forwardRef<HTMLSpanElement, BadgeProps>(
  ({ children, variant = 'neutral', size = 'md', dot = false, className = '', ...props }, ref) => {
    const variantStyles = {
      default: 'bg-surface-tertiary text-text-primary border border-border-primary',
      success: 'bg-[#EAF5E3] text-[#14532D] border border-[#14532D]/30',
      warning: 'bg-[#FEF3C7] text-[#78350F] border border-[#78350F]/30',
      danger: 'bg-[#FEE2E2] text-[#7F1D1D] border border-[#7F1D1D]/30',
      info: 'bg-[#EFF6FF] text-[#1E40AF] border border-[#1E40AF]/30',
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
  const statusConfig: Record<string, { label: string; variant: BadgeProps['variant']; icon: string }> = {
    active: { label: 'نشط', variant: 'success', icon: '✓' },
    inactive: { label: 'غير نشط', variant: 'neutral', icon: '○' },
    pending: { label: 'بانتظار الموافقة', variant: 'warning', icon: '⏱' },
    approved: { label: 'معتمد', variant: 'success', icon: '✓' },
    rejected: { label: 'مرفوض', variant: 'danger', icon: '✕' },
    suspended: { label: 'موقوف', variant: 'danger', icon: '✕' },
    searching: { label: 'جاري البحث', variant: 'info', icon: '🔍' },
    offered: { label: 'قيد العرض', variant: 'warning', icon: '⏱' },
    assigned: { label: 'مُعين', variant: 'info', icon: '🚗' },
    arrived: { label: 'وصل الكابتن', variant: 'info', icon: '📍' },
    in_progress: { label: 'قيد التنفيذ', variant: 'info', icon: '⚡' },
    completed: { label: 'مكتملة', variant: 'success', icon: '✓' },
    cancelled: { label: 'ملغية', variant: 'danger', icon: '✕' },
    online: { label: 'متصل', variant: 'success', icon: '●' },
    offline: { label: 'غير متصل', variant: 'neutral', icon: '○' },
  };

  const config = statusConfig[status] || { label: status, variant: 'neutral', icon: '' };

  return (
    <Badge variant={config.variant} className={className}>
      <span className="text-[11px] opacity-80" aria-hidden="true">{config.icon}</span>
      <span>{config.label}</span>
    </Badge>
  );
};