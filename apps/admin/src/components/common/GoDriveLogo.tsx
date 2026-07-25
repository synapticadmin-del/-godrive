import React from 'react';

interface GoDriveLogoProps {
  size?: 'sm' | 'md' | 'lg' | 'xl';
  showText?: boolean;
  className?: string;
}

export const GoDriveLogo: React.FC<GoDriveLogoProps> = ({
  size = 'md',
  showText = true,
  className = '',
}) => {
  const iconSizes = {
    sm: 'w-7 h-7',
    md: 'w-9 h-9',
    lg: 'w-12 h-12',
    xl: 'w-16 h-16',
  };

  const textSizes = {
    sm: 'text-base',
    md: 'text-xl',
    lg: 'text-2xl',
    xl: 'text-4xl',
  };

  return (
    <div dir="ltr" className={`inline-flex items-center gap-2.5 select-none ${className}`}>
      {/* GoDrive App Icon from GODRIVE.png */}
      <img
        src="/godrive-logo.png"
        alt="GoDrive"
        className={`${iconSizes[size]} object-contain rounded-xl shadow-sm flex-shrink-0`}
      />

      {showText && (
        <div dir="ltr" className="inline-flex items-baseline font-black tracking-tight leading-none">
          <span className={`text-[#53585f] dark:text-slate-100 ${textSizes[size]}`}>Go</span>
          <span className={`text-[#6bb522] ${textSizes[size]}`}>Drive</span>
        </div>
      )}
    </div>
  );
};

export default GoDriveLogo;
