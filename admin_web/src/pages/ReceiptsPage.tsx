import React from 'react';
import { PendingReceiptsTable } from '../components/PendingReceiptsTable';
import { Topbar } from '../components/Topbar';
import { useCompany } from '../lib/adminScope';
import { useCompanyOverview } from '../lib/overview';
import { usePendingReceipts } from '../lib/pendingReceipts';

/** The receipts waiting for a decision, oldest first. */
export const ReceiptsPage: React.FC = () => {
  const company = useCompany();
  const { receipts, loading, error, refresh, review, hasMore, loadMore, loadingMore } = usePendingReceipts(company.id);
  // The true number waiting (the list is loaded a part at a time): the same one the sidebar badge shows.
  const total = useCompanyOverview(company.id).data?.pending_receipts;
  return (
    <div className="space-y-6">
      <Topbar title="فحص واعتماد الإيصالات" subtitle="تصل الإيصالات الجديدة هنا فور رفعها" />
      {error && receipts.length === 0
        ? <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">تعذر تحميل الإيصالات: {error} <button className="mr-3 font-bold underline" onClick={() => void refresh()}>إعادة المحاولة</button></div>
        : <PendingReceiptsTable receipts={receipts} loading={loading} total={total} hasMore={hasMore} loadingMore={loadingMore}
            onLoadMore={loadMore} onReview={review} />}
    </div>
  );
};
