import React, { useEffect, useState } from 'react';
import { companyInitials, emblemUrl, type CompanyBrand } from '../lib/branding';

const SIZES = {
  xs: { box: 'h-5 w-5 rounded-md text-[10px]', px: 20 },
  sm: { box: 'h-8 w-8 rounded-lg text-xs', px: 32 },
  md: { box: 'h-10 w-10 rounded-xl text-sm', px: 40 },
  lg: { box: 'h-16 w-16 rounded-2xl text-xl', px: 64 },
} as const;

interface CompanyMarkProps {
  name: string | null | undefined;
  /** The company's stored marks; anything missing falls back, down to the company's initial. */
  brand?: CompanyBrand | null;
  size?: keyof typeof SIZES;
  className?: string;
}

/**
 * A company's square mark wherever a company is named: its emblem, else its
 * logo fitted in a square, else its initial. A picture that fails to load
 * (removed, offline) falls back the same way instead of showing a broken image.
 */
export const CompanyMark: React.FC<CompanyMarkProps> = ({ name, brand, size = 'md', className = '' }) => {
  const { box, px } = SIZES[size];
  const url = emblemUrl(brand, px);
  const [failed, setFailed] = useState<string | null>(null);
  useEffect(() => { setFailed(null); }, [url]);
  const frame = `${box} inline-flex flex-shrink-0 select-none items-center justify-center overflow-hidden ${className}`;
  if (url && failed !== url) {
    return (
      <span className={`${frame} border border-slate-200/80 bg-white`}>
        <img src={url} alt="" loading="lazy" decoding="async" draggable={false} onError={() => setFailed(url)}
          className="h-full w-full object-contain" />
      </span>
    );
  }
  return <span aria-hidden="true" className={`${frame} bg-[#D6EEF9] font-extrabold text-[#3E8FBF]`}>{companyInitials(name)}</span>;
};
