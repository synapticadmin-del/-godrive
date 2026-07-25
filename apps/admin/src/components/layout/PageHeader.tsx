import React from 'react';

interface PageHeaderProps {
  title: string;
  subtitle?: string;
  actions?: React.ReactNode;
  children?: React.ReactNode;
}

export function PageHeader({ title, subtitle, actions, children }: PageHeaderProps) {
  const actionContent = actions || children;
  return (
    <div className="flex flex-wrap items-start justify-between gap-3 mb-6">
      <div>
        <h1 className="text-2xl font-bold text-text-primary">{title}</h1>
        {subtitle && <p className="text-text-secondary mt-1">{subtitle}</p>}
      </div>
      {actionContent && <div className="flex items-center gap-2">{actionContent}</div>}
    </div>
  );
}

export default PageHeader;