import React, { useEffect, useMemo, useState } from 'react';
import { Badge, Button, Icon, Note } from '../../ui';
import {
  PICTURE_EDGE, PICTURE_SOURCE_TYPES, checkPictureDimensions, checkPictureFile, pictureSize, pictureUrl,
  type PictureChange, type PictureFolder,
} from '../../lib/offers';

const ACCEPT = PICTURE_SOURCE_TYPES.join(',');

/** A merchant's logo or an offer's picture where a list shows it: the picture, else a quiet tile. */
export const PictureThumb: React.FC<{ path: string | null | undefined; folder: PictureFolder; size?: number; className?: string }> = ({ path, folder, size = 40, className = '' }) => {
  const url = pictureUrl(path);
  const box = `flex-none overflow-hidden rounded-control ${className}`;
  return url
    ? <img src={url} alt="" loading="lazy" draggable={false} className={`${box} bg-ground ${folder === 'merchants' ? 'object-contain' : 'object-cover'}`} style={{ width: size, height: size }} />
    : <span aria-hidden="true" className={`${box} flex items-center justify-center bg-sunken text-ink-3`} style={{ width: size, height: size }}><Icon name={folder === 'merchants' ? 'pin' : 'image'} size={Math.round(size / 2)} /></span>;
};

/**
 * One picture of a merchant or an offer: chosen, replaced or removed here and
 * stored when the form is saved. Only the choice is kept; nothing is uploaded
 * until then.
 */
export const PictureField: React.FC<{
  folder: PictureFolder; title: string; where: string; savedPath: string | null; change: PictureChange; onChange: (change: PictureChange) => void; disabled?: boolean;
}> = ({ folder, title, where, savedPath, change, onChange, disabled = false }) => {
  const [problem, setProblem] = useState('');
  const [over, setOver] = useState(false);
  const [checking, setChecking] = useState(false);
  const fileUrl = useMemo(() => (change ? URL.createObjectURL(change) : null), [change]);
  useEffect(() => () => { if (fileUrl) URL.revokeObjectURL(fileUrl); }, [fileUrl]);
  const savedUrl = pictureUrl(savedPath);
  const shown = fileUrl ?? (change === null ? null : savedUrl);
  const logo = folder === 'merchants';

  const pick = async (file: File | undefined) => {
    if (!file || disabled) return;
    const refused = checkPictureFile(file);
    if (refused) { setProblem(refused); return; }
    setChecking(true);
    try {
      const { width, height } = await pictureSize(file);
      const unfit = checkPictureDimensions(folder, width, height);
      if (unfit) { setProblem(unfit); return; }
      setProblem('');
      onChange(file);
    } catch (error) {
      setProblem(error instanceof Error ? error.message : 'تعذر قراءة الصورة.');
    } finally {
      setChecking(false);
    }
  };

  return (
    <section aria-label={title} className="flex flex-col gap-3">
      <div>
        <h3 className="m-0 flex flex-wrap items-center gap-2 text-label font-medium">
          {title}
          {change instanceof File && <Badge tone="warning">لم تُحفظ بعد</Badge>}
          {change === null && <Badge tone="danger">ستُزال عند الحفظ</Badge>}
        </h3>
        <p className="m-0 mt-0.5 text-label text-ink-2">{where}</p>
      </div>
      <div
        onDragOver={(event) => { if (disabled) return; event.preventDefault(); setOver(true); }}
        onDragLeave={() => setOver(false)}
        onDrop={(event) => { event.preventDefault(); setOver(false); void pick(event.dataTransfer.files?.[0]); }}
        className={`flex flex-col gap-3 rounded-inner border-2 border-dashed p-3 transition-colors sm:flex-row sm:items-center ${over ? 'border-teal bg-teal-tint' : 'border-hair bg-ground'}`}
      >
        <div className={`flex flex-none items-center justify-center overflow-hidden rounded-control bg-surface shadow-ring ${logo ? 'h-24 w-24 p-2' : 'h-28 w-full sm:w-48'}`}>
          {shown
            ? <img src={shown} alt={title} draggable={false} className={logo ? 'max-h-full max-w-full object-contain' : 'h-full w-full object-cover'} />
            : <Icon name={logo ? 'pin' : 'image'} size={28} className="text-ink-3" />}
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-2">
          <div className="flex flex-wrap items-center gap-2">
            <label className={`inline-flex h-11 cursor-pointer items-center gap-1.5 rounded-control bg-surface px-3 text-label font-medium text-ink shadow-ring hover:bg-ground focus-within:shadow-focus sm:h-9 ${disabled ? 'pointer-events-none text-disabled' : ''}`}>
              <Icon name="image" size={16} /> {shown ? 'تغيير الصورة' : 'اختيار صورة'}
              <input type="file" accept={ACCEPT} className="sr-only" disabled={disabled} aria-label={`اختيار ${title}`}
                onChange={(event) => { const file = event.target.files?.[0]; event.target.value = ''; void pick(file); }} />
            </label>
            {change !== undefined ? (
              <Button sm kind="secondary" icon="undo" disabled={disabled} onClick={() => { setProblem(''); onChange(undefined); }}>
                {change === null ? 'إبقاء الحالية' : 'تراجع عن الاختيار'}
              </Button>
            ) : savedUrl && (
              <Button sm kind="dangerQuiet" icon="trash" disabled={disabled} onClick={() => { setProblem(''); onChange(null); }}>إزالة</Button>
            )}
          </div>
          <span className="text-label text-ink-3">{checking ? 'نقرأ الصورة…' : `PNG أو JPG أو WebP. تُصغَّر إلى ${PICTURE_EDGE[folder]} بكسل وتُحفظ ملفاً واحداً. ملفات SVG غير مقبولة.`}</span>
        </div>
      </div>
      {problem && <Note tone="danger">{problem}</Note>}
    </section>
  );
};
