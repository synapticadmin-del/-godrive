import React, { forwardRef } from 'react';

export interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  variant?: 'default' | 'elevated' | 'outlined' | 'filled';
  padding?: 'none' | 'sm' | 'md' | 'lg';
  hoverable?: boolean;
}

const variantClasses: Record<string, string> = {
  default: 'bg-surface-primary border border-border-primary',
  elevated: 'bg-surface-primary shadow-lg border-none',
  outlined: 'bg-transparent border-2 border-border-primary',
  filled: 'bg-surface-secondary border-none',
};

const paddingClasses: Record<string, string> = {
  none: '',
  sm: 'p-4',
  md: 'p-5',
  lg: 'p-8',
};

export const Card = forwardRef<HTMLDivElement, CardProps>(
  ({ children, variant = 'default', padding = 'md', hoverable = false, className = '', ...props }, ref) => {
    return (
      <div
        ref={ref}
        className={`rounded-xl transition-all duration-200 ${variantClasses[variant]} ${paddingClasses[padding]} ${hoverable ? 'hover:shadow-lg hover:shadow-primary-500/10 cursor-pointer' : ''} ${className}`}
        {...props}
      >
        {children}
      </div>
    );
  }
);

Card.displayName = 'Card';
export default Card;