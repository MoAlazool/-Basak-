import React, { useState } from 'react';
import { Eye, EyeOff, ShieldCheck, LogIn } from 'lucide-react';
import { BasakLogo } from '../components/BasakLogo';
import { supabase } from '../lib/supabase';
import { AdminProfile } from '../lib/adminScope';
import { loadAdminProfile } from '../lib/adminProfile';
import { useGuard } from '../lib/guard';

interface LoginPageProps {
  onLogin: (admin: AdminProfile) => void;
}

export const LoginPage: React.FC<LoginPageProps> = ({ onLogin }) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [resetNotice, setResetNotice] = useState('');

  // One request to the sign-in service at a time, whichever button or key started it.
  const guard = useGuard();
  const handlePasswordReset = () => guard('auth', async () => {
    setError('');
    setResetNotice('');
    const cleanEmail = email.trim();
    if (!cleanEmail) {
      setError('اكتب البريد الإلكتروني أولاً لإرسال رابط الاستعادة.');
      return;
    }
    setLoading(true);
    try {
      const { error: resetError } = await supabase.auth.resetPasswordForEmail(cleanEmail, {
        redirectTo: window.location.origin,
      });
      if (resetError) throw resetError;
      setResetNotice('لو البريد مسجل، هيوصلك رابط استعادة. افتحه واختر كلمة مرور جديدة.');
    } catch {
      setError('تعذر إرسال رابط الاستعادة. حاول مرة أخرى بعد قليل.');
    } finally {
      setLoading(false);
    }
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    void guard('auth', signIn);
  };
  const signIn = async () => {
    setError('');
    setLoading(true);

    try {
      const { data, error: signInError } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
      if (signInError) throw signInError;
      const admin = await loadAdminProfile(data.user.id);
      if (!admin) {
        await supabase.auth.signOut();
        throw new Error('هذا الحساب غير مسجل كمسؤول في النظام.');
      }
      onLogin(admin);
    } catch (err) {
      const message = err instanceof Error ? err.message.toLowerCase() : '';
      if (
        message.includes('invalid login credentials') ||
        message.includes('invalid_credentials') ||
        message.includes('user not found')
      ) {
        setError('البريد الإلكتروني أو كلمة المرور غير صحيحة.');
      } else if (message.includes('email not confirmed')) {
        setError('يجب تأكيد البريد الإلكتروني أولاً.');
      } else if (
        message.includes('هذا الحساب غير مسجل كمسؤول') ||
        message.includes('not registered as an administrator')
      ) {
        setError('هذا الحساب غير مسجل كمسؤول في النظام.');
      } else if (
        message.includes('fetch') ||
        message.includes('network') ||
        message.includes('timeout')
      ) {
        setError('تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مرة أخرى.');
      } else {
        setError('تعذر تسجيل الدخول. تحقق من بيانات الحساب وحاول مرة أخرى.');
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      className="min-h-screen flex items-center justify-center p-4"
      dir="rtl"
      style={{
        background: 'radial-gradient(ellipse 80% 60% at 20% 10%, #EAF7FD 0%, #F3FAFD 50%, #ffffff 100%)',
      }}
    >
      {/* Decorative blobs */}
      <div className="pointer-events-none fixed inset-0 overflow-hidden">
        <div className="absolute -top-32 -right-32 h-[400px] w-[400px] rounded-full bg-[#7EC8E3]/15 blur-3xl" />
        <div className="absolute -bottom-32 -left-32 h-[350px] w-[350px] rounded-full bg-[#A8D8F0]/10 blur-3xl" />
      </div>

      <div className="relative w-full max-w-sm">
        {/* Card */}
        <div
          className="rounded-3xl p-8 shadow-2xl"
          style={{
            background: 'rgba(255,255,255,0.72)',
            backdropFilter: 'blur(20px)',
            WebkitBackdropFilter: 'blur(20px)',
            border: '1px solid rgba(255,255,255,0.7)',
            boxShadow: '0 8px 40px rgba(126,200,227,0.22)',
          }}
        >
          {/* Logo */}
          <div className="flex flex-col items-center mb-8">
            <BasakLogo className="h-16 w-16 mb-3" />
            <h1 className="text-2xl font-extrabold text-[#1F2937]">باصك</h1>
            <p className="text-sm font-medium text-[#5B6B7A] mt-1">لوحة تحكم الإدارة</p>
          </div>

          {/* Form */}
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-xs font-bold text-[#5B6B7A] mb-1.5">
                البريد الإلكتروني للمسؤول
              </label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="admin@example.com"
                autoComplete="username"
                required
                className="w-full rounded-xl border border-slate-200 bg-white/70 px-4 py-3 text-sm text-[#1F2937] placeholder-slate-400 focus:border-[#7EC8E3] focus:outline-none focus:ring-2 focus:ring-[#7EC8E3]/20 transition"
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-[#5B6B7A] mb-1.5">
                كلمة المرور
              </label>
              <div className="relative">
                <input
                  type={showPassword ? 'text' : 'password'}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••"
                  autoComplete="current-password"
                  required
                  className="w-full rounded-xl border border-slate-200 bg-white/70 px-4 py-3 text-sm text-[#1F2937] placeholder-slate-400 focus:border-[#7EC8E3] focus:outline-none focus:ring-2 focus:ring-[#7EC8E3]/20 transition pl-12"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 transition"
                  tabIndex={-1}
                >
                  {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
              <button type="button" onClick={() => void handlePasswordReset()} disabled={loading} className="mt-2 text-xs font-bold text-[#287D9A] underline-offset-2 hover:underline disabled:opacity-50">
                نسيت كلمة المرور؟ أرسل رابط استعادة
              </button>
            </div>

            {resetNotice && <p role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-xs font-semibold text-emerald-700">{resetNotice}</p>}

            {/* Error */}
            {error && (
              <div className="rounded-xl bg-rose-50 border border-rose-200 px-4 py-3 text-xs font-semibold text-rose-700">
                {error}
              </div>
            )}

            {/* Submit */}
            <button
              type="submit"
              disabled={loading}
              className="w-full flex items-center justify-center gap-2 rounded-xl py-3 text-sm font-bold text-white transition disabled:opacity-60"
              style={{
                background: 'linear-gradient(135deg, #3E8FBF 0%, #7EC8E3 100%)',
                boxShadow: '0 4px 20px rgba(126,200,227,0.4)',
              }}
            >
              {loading ? (
                <div className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
              ) : (
                <>
                  <LogIn className="h-4 w-4" />
                  تسجيل الدخول
                </>
              )}
            </button>
          </form>

          {/* Footer */}
          <div className="mt-6 flex items-center justify-center gap-1.5 text-[11px] text-[#5B6B7A]">
            <ShieldCheck className="h-3.5 w-3.5 text-[#3E8FBF]" />
            <span>وصول مقيد للإدارة فقط</span>
          </div>
        </div>
      </div>
    </div>
  );
};
