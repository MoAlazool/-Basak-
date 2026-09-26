import React, { useState } from 'react';
import { supabase } from '../lib/supabase';
import { FileCheck, Check, X, Eye, AlertOctagon, Clock } from 'lucide-react';

export interface PendingReceiptRow {
  id: string;
  subscriptionId: string;
  studentName: string;
  studentPhone: string;
  university: string;
  lineName: string;
  subscriptionType: string;
  price: number;
  imageUrl: string;
  attemptNumber: number;
  createdAt: string;
}

interface PendingReceiptsProps {
  receipts: PendingReceiptRow[];
  loading: boolean;
  onReceiptReviewed: (receiptId: string) => void;
}

export const PendingReceiptsTable: React.FC<PendingReceiptsProps> = ({
  receipts,
  loading,
  onReceiptReviewed,
}) => {
  const [rejectModalReceiptId, setRejectModalReceiptId] = useState<string | null>(null);
  const [rejectionReason, setRejectionReason] = useState('');
  const [processingId, setProcessingId] = useState<string | null>(null);
  const [previewImageUrl, setPreviewImageUrl] = useState<string | null>(null);

  // Approve Receipt Mutation
  const handleApprove = async (receiptId: string) => {
    try {
      setProcessingId(receiptId);
      const { error } = await supabase
        .from('receipts')
        .update({ status: 'approved' })
        .eq('id', receiptId);

      if (error) throw error;
      // Optimistic update: notify parent to remove or fade out row
      onReceiptReviewed(receiptId);
    } catch (err: any) {
      alert('خطأ أثناء اعتماد الإيصال: ' + err.message);
    } finally {
      setProcessingId(null);
    }
  };

  // Reject Receipt Mutation (Mandatory reason strictly enforced)
  const handleConfirmReject = async () => {
    if (!rejectModalReceiptId) return;
    const cleanReason = rejectionReason.trim();
    if (!cleanReason) {
      alert('سبب الرفض إلزامي ولا يمكن إتمام الرفض بدونه.');
      return;
    }

    try {
      setProcessingId(rejectModalReceiptId);
      const { error } = await supabase
        .from('receipts')
        .update({
          status: 'rejected',
          rejection_reason: cleanReason,
        })
        .eq('id', rejectModalReceiptId);

      if (error) throw error;
      onReceiptReviewed(rejectModalReceiptId);
      setRejectModalReceiptId(null);
      setRejectionReason('');
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
        ) : (
          <table className="w-full text-right text-[13.5px]">
            <thead className="border-b border-slate-100 text-[#5B6B7A] text-[12px] font-bold uppercase">
              <tr>
                <th className="py-3 px-4">الطالب</th>
                <th className="py-3 px-4">خط السير</th>
                <th className="py-3 px-4">نوع الاشتراك</th>
                <th className="py-3 px-4">المبلغ</th>
                <th className="py-3 px-4">المحاولة</th>
                <th className="py-3 px-4">وقت الرفع</th>
                <th className="py-3 px-4 text-center">الإجراءات</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {receipts.map((row) => {
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
                        <div
                          onClick={() => setPreviewImageUrl(row.imageUrl)}
                          className="h-10 w-10 rounded-xl bg-slate-100 border border-slate-200 overflow-hidden flex items-center justify-center cursor-pointer hover:border-[#7EC8E3] group"
                          title="عرض صورة الإيصال"
                        >
                          <Eye className="h-4 w-4 text-[#5B6B7A] group-hover:text-[#3E8FBF]" />
                        </div>
                        <div>
                          <p className="font-bold text-[#1F2937] leading-tight">{row.studentName}</p>
                          <p className="text-[11.5px] text-[#5B6B7A]">{row.studentPhone} • {row.university}</p>
                        </div>
                      </div>
                    </td>

                    {/* Line */}
                    <td className="py-3.5 px-4 font-semibold text-[#1F2937]">
                      {row.lineName}
                    </td>

                    {/* Subscription Type */}
                    <td className="py-3.5 px-4">
                      <span className="pill-new">
                        {row.subscriptionType === 'yearly' ? 'سنوي' : 'فصلي (ترم)'}
                      </span>
                    </td>

                    {/* Price */}
                    <td className="py-3.5 px-4 font-extrabold text-[#3E8FBF]">
                      {row.price} ج.م
                    </td>

                    {/* Attempt number */}
                    <td className="py-3.5 px-4 text-[#5B6B7A] text-[12.5px]">
                      {row.attemptNumber} من 5
                    </td>

                    {/* Upload time */}
                    <td className="py-3.5 px-4 text-[#5B6B7A] text-[12px]">
                      <div className="flex items-center gap-1.5">
                        <Clock className="h-3.5 w-3.5 text-slate-400" />
                        <span>{new Date(row.createdAt).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}</span>
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
      {previewImageUrl && (
        <div
          onClick={() => setPreviewImageUrl(null)}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4"
        >
          <div className="glass-panel p-4 max-w-lg w-full bg-white">
            <div className="flex justify-between items-center mb-2">
              <span className="text-sm font-bold text-[#1F2937]">معاينة إيصال التحويل</span>
              <button onClick={() => setPreviewImageUrl(null)} className="text-slate-400 hover:text-slate-600">
                <X className="h-5 w-5" />
              </button>
            </div>
            <div className="h-80 bg-slate-100 rounded-xl overflow-hidden flex items-center justify-center border border-slate-200">
              <span className="text-xs text-[#5B6B7A]">معاينة الصورة المسجلة في Supabase Storage</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
