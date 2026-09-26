import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Users, Bus, TrendingUp, AlertCircle } from 'lucide-react';

export const Dashboard: React.FC = () => {
  const [stats, setStats] = useState({
    activeSubscribers: 0,
    todayRiders: 0,
    activeLines: 0,
    totalCompanies: 0,
    pendingReceipts: 0,
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchDashboardStats();
  }, []);

  const fetchDashboardStats = async () => {
    try {
      setLoading(true);
      // 1. Active Subscriptions
      const { count: subsCount } = await supabase
        .from('subscriptions')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'active');

      // 2. Active Lines
      const { count: linesCount } = await supabase
        .from('lines')
        .select('*', { count: 'exact', head: true })
        .eq('is_active', true);

      // 3. Companies
      const { count: companiesCount } = await supabase
        .from('companies')
        .select('*', { count: 'exact', head: true })
        .eq('is_active', true);

      // 4. Pending Receipts
      const { count: receiptsCount } = await supabase
        .from('receipts')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'pending');

      // 5. Today's Riders
      const today = new Date().toISOString().substring(0, 10);
      const { count: ridersCount } = await supabase
        .from('daily_ride_status')
        .select('*', { count: 'exact', head: true })
        .eq('ride_date', today)
        .eq('is_riding', true);

      setStats({
        activeSubscribers: subsCount || 0,
        todayRiders: ridersCount || 0,
        activeLines: linesCount || 0,
        totalCompanies: companiesCount || 0,
        pendingReceipts: receiptsCount || 0,
      });
    } catch (err) {
      console.error('Error fetching stats:', err);
    } finally {
      setLoading(false);
    }
  };

  const statCards = [
    {
      title: 'إجمالي المشتركين النشطين',
      value: stats.activeSubscribers,
      icon: Users,
      color: 'bg-blue-500',
      lightColor: 'bg-blue-50 text-blue-700',
    },
    {
      title: 'ركاب اليوم (نازل اليوم)',
      value: stats.todayRiders,
      icon: Bus,
      color: 'bg-teal-500',
      lightColor: 'bg-teal-50 text-teal-700',
    },
    {
      title: 'إيصالات قيد المراجعة',
      value: stats.pendingReceipts,
      icon: AlertCircle,
      color: 'bg-amber-500',
      lightColor: 'bg-amber-50 text-amber-700',
    },
    {
      title: 'الخطوط العاملة',
      value: stats.activeLines,
      icon: TrendingUp,
      color: 'bg-indigo-500',
      lightColor: 'bg-indigo-50 text-indigo-700',
    },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">لوحة المتابعة العامة</h1>
        <p className="text-sm text-slate-500">نظرة عامة على الاشتراكات والركاب والخطوط اليوم</p>
      </div>

      {loading ? (
        <div className="flex h-48 items-center justify-center">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {statCards.map((card, i) => {
            const Icon = card.icon;
            return (
              <div
                key={i}
                className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm transition hover:shadow-md"
              >
                <div className="flex items-center justify-between">
                  <div className={`rounded-xl p-3 ${card.lightColor}`}>
                    <Icon className="h-6 w-6" />
                  </div>
                </div>
                <div className="mt-4">
                  <h3 className="text-sm font-medium text-slate-500">{card.title}</h3>
                  <p className="mt-1 text-2xl font-bold text-slate-800">{card.value}</p>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Quick info banner */}
      <div className="rounded-2xl border border-sky-100 bg-sky-50/60 p-5">
        <h3 className="font-bold text-sky-900">ملاحظة تنظيمية هامة</h3>
        <p className="mt-1 text-sm text-sky-700 leading-relaxed">
          يتم إعادة تعيين مفتاح حضور الطلاب "نازل بكرة" تلقائياً كل يوم في تمام الساعة 1:00 ظهراً عبر الـ Supabase Edge Function، ومسح الـ QR من قِبل المشرفين هو للاطلاع على بيانات الطالب فقط ولا يسجل حضوراً.
        </p>
      </div>
    </div>
  );
};
