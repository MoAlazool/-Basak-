import { useCallback, useEffect, useState } from 'react';
import { supabase } from './supabase';

export interface PendingReceiptRow {
  id: string;
  subscriptionId: string;
  studentName: string;
  studentPhone: string;
  university: string;
  lineName: string;
  subscriptionType: string;
  price: number;
  imagePath: string | null;
  imageUrl: string | null;
  attemptNumber: number;
  createdAt: string;
}

function decodeStoragePath(path: string): string {
  return path.split('/').map((part) => {
    try { return decodeURIComponent(part); } catch { return part; }
  }).join('/');
}

/** Accepts both current storage object paths and legacy Supabase object URLs. */
export function normalizeReceiptStoragePath(value: string | null | undefined): string | null {
  if (!value) return null;
  const raw = value.trim();
  if (!raw) return null;

  let candidate = raw;
  if (/^https?:\/\//i.test(raw)) {
    try {
      const pathname = new URL(raw).pathname;
      const bucketMarker = '/receipts/';
      const bucketIndex = pathname.indexOf(bucketMarker);
      if (bucketIndex < 0) return null;
      candidate = pathname.slice(bucketIndex + bucketMarker.length);
    } catch {
      return null;
    }
  } else {
    candidate = candidate.split(/[?#]/, 1)[0];
    candidate = candidate.replace(/^\/+/, '');
    candidate = candidate.replace(/^receipts\//i, '');
    const objectMarker = /^(?:storage\/v1\/)?object\/(?:public|sign|authenticated)\/receipts\//i;
    candidate = candidate.replace(objectMarker, '');
  }

  const decoded = decodeStoragePath(candidate.replace(/^\/+/, ''));
  return decoded && !decoded.split('/').some((part) => part === '..') ? decoded : null;
}

export async function createReceiptImageUrl(reference: string | null | undefined): Promise<string> {
  if (!reference?.trim()) throw new Error('مسار صورة الإيصال غير متاح.');
  const storagePath = normalizeReceiptStoragePath(reference);
  if (!storagePath) {
    if (/^https?:\/\//i.test(reference)) return reference;
    throw new Error('مسار صورة الإيصال غير صالح.');
  }

  const { data, error } = await supabase.storage.from('receipts').createSignedUrl(storagePath, 3600);
  if (error) throw error;
  return data.signedUrl;
}

export async function fetchPendingReceipts(): Promise<PendingReceiptRow[]> {
  const { data, error } = await supabase.from('receipts').select(`
    id, image_url, attempt_number, created_at, subscription_id,
    subscriptions(
      id, type, price,
      students(full_name, phone, university),
      lines(name)
    )
  `).eq('status', 'pending').order('created_at', { ascending: true });
  if (error) throw error;

  return Promise.all((data || []).map(async (receipt: any) => {
    const imagePath = normalizeReceiptStoragePath(receipt.image_url);
    let imageUrl: string | null = null;
    try {
      imageUrl = await createReceiptImageUrl(receipt.image_url);
    } catch (imageError) {
      // Keep the receipt visible even if its file needs a fresh URL or has been removed.
      console.warn(`Could not create a preview URL for receipt ${receipt.id}:`, imageError);
    }

    const subscription = receipt.subscriptions;
    const student = subscription?.students;
    return {
      id: receipt.id,
      subscriptionId: receipt.subscription_id,
      studentName: student?.full_name || 'طالب جديد',
      studentPhone: student?.phone || '-',
      university: student?.university || 'الجامعة',
      lineName: subscription?.lines?.name || '-',
      subscriptionType: subscription?.type || 'termly',
      price: Number(subscription?.price || 0),
      imagePath,
      imageUrl,
      attemptNumber: receipt.attempt_number || 1,
      createdAt: receipt.created_at,
    };
  }));
}

/** One shared query keeps the dashboard and the dedicated receipt page in sync. */
export function usePendingReceipts() {
  const [receipts, setReceipts] = useState<PendingReceiptRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      setReceipts(await fetchPendingReceipts());
    } catch (loadError) {
      console.error('Could not load pending receipts:', loadError);
      setError(loadError instanceof Error ? loadError.message : 'تعذر تحميل الإيصالات.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    let inFlight = false;
    const loadIfVisible = () => {
      if (inFlight || document.visibilityState !== 'visible') return;
      inFlight = true;
      void refresh().finally(() => { inFlight = false; });
    };

    loadIfVisible();
    const channel = supabase
      .channel('admin-pending-receipts')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'receipts' }, loadIfVisible)
      .subscribe();
    const interval = window.setInterval(loadIfVisible, 30_000);
    window.addEventListener('focus', loadIfVisible);
    document.addEventListener('visibilitychange', loadIfVisible);

    return () => {
      window.clearInterval(interval);
      window.removeEventListener('focus', loadIfVisible);
      document.removeEventListener('visibilitychange', loadIfVisible);
      void supabase.removeChannel(channel);
    };
  }, [refresh]);

  return { receipts, loading, error, refresh };
}
