import React, { useState } from 'react';
import { ArrowRight, Bus, Eye, EyeOff, LockKeyhole } from 'lucide-react';
import { supabase } from '../lib/supabase';

interface ResetPasswordPageProps {
  onComplete: () => void;
}

export const ResetPasswordPage: React.FC<ResetPasswordPageProps> = ({ onComplete }) => {
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError('');
    if (password.length < 8) {
      setError('كلمة المرور يجب أن تكون 8 أحرف على الأقل.');
      return;
    }
    if (password !== confirmation) {
      setError('كلمتا المرور غير متطابقتين.');
      return;
    }

    setLoading(true);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) throw new Error('رابط الاستعادة انتهت صلاحيته. ارجع لصفحة الدخول واطلب رابطاً جديداً.');
      const { error: updateError } = await supabase.auth.updateUser({ password });
      if (updateError) throw updateError;
      await supabase.auth.signOut();
      window.history.replaceState({}, document.title, window.location.pathname);
      onComplete();
    } catch (resetError) {
      const message = resetError instanceof Error ? resetError.message : '';
      setError(message.includes('expired') || message.includes('انتهت')
        ? 'رابط الاستعادة انتهت صلاحيته. ارجع لصفحة الدخول واطلب رابطاً جديداً.'
        : 'تعذر تغيير كلمة المرور. اطلب رابط استعادة جديداً وحاول مرة أخرى.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="min-h-screen flex items-center justify-center p-4" dir="rtl" style={{ background: 'radial-gradient(ellipse 80% 60% at 20% 10%, #EAF7FD 0%, #F3FAFD 50%, #ffffff 100%)' }}>
      <section className="w-full max-w-md rounded-3xl border border-white/70 bg-white/80 p-8 shadow-2xl backdrop-blur-xl">
        <div className="mb-7 flex flex-col items-center text-center">
          <div className="mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-tr from-[#1F6F8B] to-[#7EC8E3] text-white shadow-lg"><Bus className="h-7 w-7" /></div>
          <h1 className="text-2xl font-extrabold text-slate-800">تعيين كلمة مرور جديدة</h1>
          <p className="mt-2 text-sm text-slate-500">اختر كلمة مرور لحساب إدارة باصك.</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <label className="block text-sm font-bold text-slate-600">
            كلمة المرور الجديدة
            <div className="relative mt-2">
              <LockKeyhole className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
              <input required minLength={8} autoComplete="new-password" type={showPassword ? 'text' : 'password'} value={password} onChange={(event) => setPassword(event.target.value)} className="w-full rounded-xl border border-slate-200 bg-white px-10 py-3 text-sm font-normal text-slate-800 outline-none transition focus:border-sky-300 focus:ring-2 focus:ring-sky-100" placeholder="8 أحرف على الأقل" />
              <button type="button" aria-label={showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'} onClick={() => setShowPassword((shown) => !shown)} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">{showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}</button>
            </div>
          </label>

          <label className="block text-sm font-bold text-slate-600">
            تأكيد كلمة المرور
            <input required minLength={8} autoComplete="new-password" type={showPassword ? 'text' : 'password'} value={confirmation} onChange={(event) => setConfirmation(event.target.value)} className="mt-2 w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm font-normal text-slate-800 outline-none transition focus:border-sky-300 focus:ring-2 focus:ring-sky-100" placeholder="أعد كتابة كلمة المرور" />
          </label>

          {error && <p role="alert" className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">{error}</p>}

          <button disabled={loading} className="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-l from-[#1F6F8B] to-[#3E8FBF] py-3 font-bold text-white shadow-lg shadow-sky-200 transition disabled:opacity-60">
            <ArrowRight className="h-4 w-4" />
            {loading ? 'جاري حفظ كلمة المرور...' : 'حفظ كلمة المرور'}
          </button>
        </form>
      </section>
    </main>
  );
};
