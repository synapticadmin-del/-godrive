import React from 'react';

interface TempoLogoProps {
  size?: 'sm' | 'md' | 'lg' | 'xl';
  showText?: boolean;
  showImage?: boolean;
  className?: string;
}

/**
 * The Tempo lockup for the admin.
 *
 * Mirrors `TempoWordmark` in the Flutter shared package: the trailing "o"
 * carries the brand accent while the rest of the word takes the surface's text
 * colour. Keeping the two implementations in step matters more than it looks —
 * the admin and the apps are the same brand seen by the same operators, and a
 * lockup that splits differently in each reads as two products.
 */
export const TempoLogo: React.FC<TempoLogoProps> = ({
  size = 'md',
  showText = true,
  showImage = false,
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
      {/* Optional App Icon */}
      {showImage && (
        <img
          src="/tempo-logo.png"
          alt="Tempo"
          className={`${iconSizes[size]} object-contain rounded-xl shadow-sm flex-shrink-0`}
        />
      )}

      {showText && (
        <div dir="ltr" className="inline-flex items-baseline font-black tracking-tight leading-none">
          <span className={`text-[#53585f] dark:text-slate-100 ${textSizes[size]}`}>Temp</span>
          <span className={`text-[#1472ed] ${textSizes[size]}`}>o</span>
        </div>
      )}
    </div>
  );
};

export default TempoLogo;
