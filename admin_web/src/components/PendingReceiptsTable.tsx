import React, { useMemo, useState } from 'react';
import { supabase } from '../lib/supabase';
import { FileCheck, Check, X, Eye, AlertOctagon, Clock, Building2, MapPin, Phone, GraduationCap, Search } from 'lucide-react';
import { createReceiptImageUrl, type PendingReceiptRow } from '../lib/pendingReceipts';

export type { PendingReceiptRow } from '../lib/pendingReceipts';

const typeLabels: Record<string, string> = { termly: 'فصلي (ترم)', yearly: 'سنوي', daily: 'يومي' };
const formatUpload = (iso: string) => {
  const date = new Date(iso);
  return {
    day: date.toLocaleDateString('ar-EG', { day: 'numeric', month: 'short' }),
    time: date.toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' }),
  };
};

interface PendingReceiptsProps {
  receipts: PendingReceiptRow[];
  loading: boolean;
  /** Saves the decision. The row disappears at once and returns if the save fails. */
  onReview: (receiptId: string, decision: 'approved' | 'rejected', reason?: string) => Promise<void>;
}

export const PendingReceiptsTable: React.FC<PendingReceiptsProps> = ({
  receipts,
  loading,
  onReview,
}) => {
  const [rejectModalReceiptId, setRejectModalReceiptId] = useState<string | null>(null);
  const [rejectionReason, setRejectionReason] = useState('');
  const [processingId, setProcessingId] = useState<string | null>(null);
  const [thumbnailFailures, setThumbnailFailures] = useState<Record<string, boolean>>({});
  const [previewImageUrl, setPreviewImageUrl] = useState<string | null>(null);
  const [previewReceipt, setPreviewReceipt] = useState<PendingReceiptRow | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewError, setPreviewError] = useState('');
  const [query, setQuery] = useState('');

  const visibleReceipts = useMemo(() => {
    const q = query.trim().toLowerCase();
    return receipts.filter((row) =>
      !q || [row.studentName, row.studentPhone, row.lineName, row.university]
        .some((value) => value.toLowerCase().includes(q)));
  }, [receipts, query]);

  const openReceiptPreview = async (row: PendingReceiptRow) => {
    setPreviewReceipt(row);
    setPreviewImageUrl(null);
    setPreviewError('');
    setPreviewLoading(true);
    try {
      // Create a fresh URL at click time so previews still work after a tab has
      // been open long enough for the list's original signed URL to expire.
      const url = await createReceiptImageUrl(row.imagePath || row.imageUrl);
      setPreviewImageUrl(url);
    } catch (error) {
      setPreviewError(error instanceof Error ? error.message : 'تعذر تحميل صورة الإيصال.');
    } finally {
      setPreviewLoading(false);
    }
  };

  const handleApprove = async (receiptId: string) => {
    try {
      setProcessingId(receiptId);
      await onReview(receiptId, 'approved');
    } catch (err: any) {
      alert('خطأ أثناء اعتماد الإيصال: ' + err.message);
    } finally {
      setProcessingId(null);
    }
  };

  // A written reason is mandatory for a rejection.
  const handleConfirmReject = async () => {
    if (!rejectModalReceiptId) return;
    const cleanReason = rejectionReason.trim();
    if (!cleanReason) {
      alert('سبب الرفض إلزامي ولا يمكن إتمام الرفض بدونه.');
      return;
    }
    const receiptId = rejectModalReceiptId;
    try {
      setProcessingId(receiptId);
      setRejectModalReceiptId(null);
      setRejectionReason('');
      await onReview(receiptId, 'rejected', cleanReason);
    } catch (err: any) {
      alert('خطأ أثناء رفض الإيصال: ' + err.message);
    } finally {
      setProcessingId(null);
    }
  };

  return (
    <div className="glass-panel p-6">
      {/* Header */}
      <div className="flex items-center justify-between pb-4 border-b border-slate-100">
        <div className="flex items-center gap-2.5">
          <div className="h-8 w-8 rounded-lg bg-[#FFF1D6] flex items-center justify-center text-[#B8860B]">
            <FileCheck className="h-4 w-4" />
          </div>
          <div>
            <h2 className="text-[16px] font-bold text-[#1F2937]">طابور فحص الإيصالات المعلقة</h2>
            <p className="text-[12px] font-medium text-[#5B6B7A]">
              مراجعة التحويلات البنكية للاشتراكات الجديدة واتخاذ قرار القبول أو الرفض ببيان السبب
            </p>
          </div>
        </div>
        <span className="pill-pending">
          {receipts.length} إيصالات قيد الانتظار
        </span>
      </div>

      {receipts.length > 0 && (
        <div className="mt-4 flex flex-wrap items-center gap-3">
          <div className="relative min-w-[220px] flex-1">
            <Search className="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="بحث باسم الطالب، الهاتف أو الخط..." className="w-full rounded-xl border border-slate-200 bg-white py-2 pl-3 pr-9 text-xs focus:border-[#7EC8E3] focus:outline-none" />
          </div>
        </div>
      )}

      {/* Table */}
      <div className="mt-4 overflow-x-auto">
        {loading ? (
          <div className="py-12 text-center text-sm text-[#5B6B7A]">جاري تحميل الإيصالات المعلقة...</div>
        ) : receipts.length === 0 ? (
          <div className="py-12 text-center">
            <div className="h-12 w-12 rounded-full bg-[#DDF3E6] text-[#2E9E5B] flex items-center justify-center mx-auto mb-2">
              <Check className="h-6 w-6" />
            </div>
            <h3 className="text-sm font-bold text-[#1F2937]">لا توجد إيصالات معلقة حالياً</h3>
            <p className="text-xs text-[#5B6B7A] mt-1">تمت مراجعة واعتماد كافة طلبات الاشتراكات بنجاح.</p>
          </div>
        ) : visibleReceipts.length === 0 ? (
          <div className="py-10 text-center text-sm text-[#5B6B7A]">لا توجد إيصالات مطابقة للبحث.</div>
        ) : (
          <table className="w-full min-w-[920px] text-right text-[13.5px]">
            <thead className="border-b border-slate-100 text-[#5B6B7A] text-[12px] font-bold uppercase">
              <tr>
                <th className="py-3 px-4">الطالب</th>
                <th className="py-3 px-4">الشركة وخط السير</th>
                <th className="py-3 px-4">الاشتراك والمبلغ</th>
                <th className="py-3 px-4">المحاولة</th>
                <th className="py-3 px-4">وقت الرفع</th>
                <th className="py-3 px-4 text-center">الإجراءات</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {visibleReceipts.map((row) => {
                const isProcessing = processingId === row.id;
                return (
                  <tr
                    key={row.id}
                    className={`hover:bg-white/70 transition-colors ${
                      isProcessing ? 'opacity-50 pointer-events-none' : ''
                    }`}
                  >
                    {/* Student Info with Thumbnail */}
                    <td className="py-3.5 px-4">
                      <div className="flex items-center gap-3">
                        <button
                          type="button"
                          onClick={() => void openReceiptPreview(row)}
                          className="h-10 w-10 rounded-xl bg-slate-100 border border-slate-200 overflow-hidden flex items-center justify-center cursor-pointer hover:border-[#7EC8E3] group"
                          title="عرض صورة الإيصال"
                          aria-label={`عرض إيصال ${row.studentName}`}
                        >
                          {row.imageUrl && !thumbnailFailures[row.id] ? (
                            <img
                              src={row.imageUrl}
                              alt=""
                              className="h-full w-full object-cover"
                              onError={() => setThumbnailFailures((failed) => ({ ...failed, [row.id]: true }))}
                            />
                          ) : (
                            <Eye className="h-4 w-4 text-[#5B6B7A] group-hover:text-[#3E8FBF]" />
                          )}
                        </button>
                        <div className="min-w-0 space-y-0.5">
                          <p className="font-bold text-[#1F2937] leading-tight">{row.studentName}</p>
                          <p className="flex items-center gap-1 text-[11.5px] text-[#5B6B7A]" dir="rtl"><Phone className="h-3 w-3" /><span dir="ltr">{row.studentPhone}</span></p>
                          <p className="flex items-center gap-1 text-[11.5px] text-[#5B6B7A]"><GraduationCap className="h-3 w-3" />{row.university}{row.college ? ` • ${row.college}` : ''}</p>
                        </div>
                      </div>
                    </td>

                    {/* Company / Line / Station */}
                    <td className="py-3.5 px-4">
                      <div className="space-y-1">
                        <span className="inline-flex items-center gap-1 rounded-md bg-sky-50 px-2 py-0.5 text-[11.5px] font-bold text-sky-700"><Building2 className="h-3 w-3" />{row.companyName}</span>
                        <p className="font-semibold text-[#1F2937]">{row.lineName}</p>
                        <p className="flex items-center gap-1 text-[11.5px] text-[#5B6B7A]"><MapPin className="h-3 w-3" />{row.stationName}</p>
                        {(row.departureTime || row.returnTime) && (
                          <p className="text-[11px] text-[#5B6B7A]">ذهاب <span dir="ltr">{row.departureTime || '—'}</span> • عودة <span dir="ltr">{row.returnTime || '—'}</span></p>
                        )}
                      </div>
                    </td>

                    {/* Subscription Type + Price */}
                    <td className="py-3.5 px-4">
                      <span className="pill-new">{typeLabels[row.subscriptionType] || row.subscriptionType}</span>
                      {row.periodLabel && <p className="mt-1 text-[11.5px] font-bold text-[#1F2937]">{row.periodLabel}</p>}
                      {row.periodStart && (
                        <p className="text-[11px] text-[#5B6B7A]">
                          <span dir="ltr">{row.periodStart} → {row.periodEnd}</span>
                          {row.periodPhase === 'upcoming' && <span className="mr-1 rounded bg-indigo-50 px-1.5 text-[10px] font-bold text-indigo-700">دفع مقدم</span>}
                        </p>
                      )}
                      <p className="mt-1 font-extrabold text-[#3E8FBF]">{row.price.toLocaleString('ar-EG')} ج.م</p>
                    </td>

                    {/* Attempt number */}
                    <td className="py-3.5 px-4 text-[#5B6B7A] text-[12.5px]">
                      {row.attemptNumber} من 5
                    </td>

                    {/* Upload time */}
                    <td className="py-3.5 px-4 text-[#5B6B7A] text-[12px]">
                      <div className="flex items-center gap-1.5">
                        <Clock className="h-3.5 w-3.5 text-slate-400" />
                        <span>{formatUpload(row.createdAt).day} — {formatUpload(row.createdAt).time}</span>
                      </div>
                    </td>

                    {/* Actions: Approve / Reject */}
                    <td className="py-3.5 px-4">
                      <div className="flex items-center justify-center gap-2">
                        <button
                          onClick={() => handleApprove(row.id)}
                          disabled={isProcessing}
                          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#2E9E5B] text-white text-xs font-bold hover:bg-[#25854c] transition shadow-sm"
                        >
                          <Check className="h-3.5 w-3.5" />
                          قبول
                        </button>
                        <button
                          onClick={() => {
                            setRejectModalReceiptId(row.id);
                            setRejectionReason('');
                          }}
                          disabled={isProcessing}
                          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#DC2626] text-white text-xs font-bold hover:bg-[#b91c1c] transition shadow-sm"
                        >
                          <X className="h-3.5 w-3.5" />
                          رفض
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {/* Mandatory Rejection Reason Modal */}
      {rejectModalReceiptId && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm p-4">
          <div className="w-full max-w-md glass-panel bg-white p-6 shadow-2xl">
            <div className="flex items-center gap-2 text-[#DC2626] mb-3">
              <AlertOctagon className="h-5 w-5" />
              <h3 className="text-base font-bold">سبب رفض إيصال التحويل</h3>
            </div>
            <p className="text-xs text-[#5B6B7A] leading-relaxed mb-4">
              بحسب لوائح النظام، سبب الرفض إلزامي حتى يتمكن الطالب من معرفة سبب عدم القبول وإعادة الرفع (بحد أقصى 4 مرات إضافية).
            </p>

            <textarea
              rows={3}
              value={rejectionReason}
              onChange={(e) => setRejectionReason(e.target.value)}
              placeholder="اكتب سبب الرفض هنا (مثال: صورة التحويل غير واضحة، المبلغ غير مطابق، رقم العملية مقطوع)..."
              className="w-full rounded-xl border border-slate-200 p-3 text-sm focus:border-[#7EC8E3] focus:outline-none"
            />

            <div className="mt-4 flex justify-end gap-2.5">
              <button
                onClick={() => setRejectModalReceiptId(null)}
                className="px-4 py-2 rounded-xl border border-slate-200 text-xs font-semibold text-[#5B6B7A] hover:bg-slate-50 transition"
              >
                إلغاء
              </button>
              <button
                onClick={handleConfirmReject}
                className="px-5 py-2 rounded-xl bg-[#DC2626] text-white text-xs font-bold hover:bg-[#b91c1c] transition shadow-md"
              >
                تأكيد الرفض
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Image Preview Modal */}
      {previewReceipt && (
        <div
          onClick={() => {
            setPreviewReceipt(null);
            setPreviewImageUrl(null);
            setPreviewError('');
          }}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4"
        >
          <div className="glass-panel p-4 max-w-lg w-full bg-white">
            <div className="flex justify-between items-center mb-2">
              <div>
                <span className="text-sm font-bold text-[#1F2937]">إيصال {previewReceipt.studentName}</span>
                <p className="text-[11.5px] text-[#5B6B7A]">{previewReceipt.companyName} • {previewReceipt.lineName} • {previewReceipt.periodLabel || typeLabels[previewReceipt.subscriptionType] || previewReceipt.subscriptionType} • {previewReceipt.price.toLocaleString('ar-EG')} ج.م • رُفع {formatUpload(previewReceipt.createdAt).day} {formatUpload(previewReceipt.createdAt).time}</p>
              </div>
              <button onClick={() => setPreviewReceipt(null)} className="text-slate-400 hover:text-slate-600">
                <X className="h-5 w-5" />
              </button>
            </div>
            <div className="h-80 bg-slate-100 rounded-xl overflow-hidden flex items-center justify-center border border-slate-200">
              {previewLoading ? (
                <span className="text-sm text-slate-500">جاري تحميل صورة الإيصال...</span>
              ) : previewError ? (
                <div className="px-6 text-center text-sm text-rose-700" role="alert">
                  <p>تعذر عرض صورة الإيصال: {previewError}</p>
                  <button className="mt-3 font-bold underline" onClick={() => void openReceiptPreview(previewReceipt)}>
                    إعادة المحاولة
                  </button>
                </div>
              ) : previewImageUrl ? (
                <img
                  src={previewImageUrl}
                  alt="إيصال التحويل"
                  className="h-full w-full object-contain"
                  onError={() => {
                    setPreviewImageUrl(null);
                    setPreviewError('تعذر فتح الملف. تحقق من أن صورة الإيصال ما زالت محفوظة.');
                  }}
                />
              ) : null}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
