import React from 'react';
import basakLogo from '../assets/basak-logo.png';

interface BasakLogoProps {
  className?: string;
}

/** The circular BASAK app icon, shared with the mobile app. */
export const BasakLogo: React.FC<BasakLogoProps> = ({ className = 'h-10 w-10' }) => (
  <img
    src={basakLogo}
    alt="باصك"
    draggable={false}
    className={`${className} flex-shrink-0 rounded-full object-cover shadow-md shadow-[#7EC8E3]/30`}
  />
);
