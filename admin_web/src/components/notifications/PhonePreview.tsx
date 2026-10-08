import React from 'react';
import { BasakLogo } from '../BasakLogo';

/**
 * How the notification reads on a phone. A sketch of the wording only: each
 * phone draws its own notifications, and this says nothing about arrival.
 */
export const PhonePreview: React.FC<{ title: string; body: string; high?: boolean }> = ({ title, body, high }) => (
  <div className="mx-auto w-full max-w-[270px] rounded-[28px] border border-slate-200 bg-gradient-to-b from-slate-700 to-slate-900 p-3 shadow-sm" aria-label="معاينة الإشعار على الهاتف">
    <div className="mx-auto mb-3 h-1.5 w-14 rounded-full bg-white/20" />
    <div className="rounded-2xl bg-white/95 p-3 text-right shadow">
      <div className="flex items-center gap-2 text-[11px] text-slate-500">
        <BasakLogo className="h-4 w-4" />
        <span className="font-bold text-slate-700">باصك</span>
        <span className="mr-auto">الآن</span>
      </div>
      <p className={`mt-1.5 break-words text-[13px] font-bold ${title.trim() ? 'text-slate-900' : 'text-slate-300'}`}>
        {title.trim() || 'عنوان الإشعار'}
      </p>
      <p className={`mt-0.5 line-clamp-4 whitespace-pre-line break-words text-xs leading-5 ${body.trim() ? 'text-slate-600' : 'text-slate-300'}`}>
        {body.trim() || 'نص الإشعار يظهر هنا كما يقرؤه الطالب.'}
      </p>
    </div>
    <p className="mt-3 text-center text-[10px] leading-4 text-white/60">
      {high ? 'أولوية عالية · ' : ''}شكل تقريبي، ويختلف من هاتف لآخر
    </p>
  </div>
);
