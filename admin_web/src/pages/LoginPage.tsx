import React, { useState } from 'react';
import { Bus, Eye, EyeOff, ShieldCheck, LogIn } from 'lucide-react';
import { supabase } from '../lib/supabase';

interface LoginPageProps {
  onLogin: () => void;
}

export const LoginPage: React.FC<LoginPageProps> = ({ onLogin }) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const { data, error: signInError } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
      if (signInError) throw signInError;
      const { data: admin, error: adminError } = await supabase.from('admins').select('id').eq('id', data.user.id).maybeSingle();
      if (adminError) throw adminError;
      if (!admin) {
        await supabase.auth.signOut();
        throw new Error('هذا الحساب غير مسجل كمسؤول في النظام.');
      }
      onLogin();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'تعذر تسجيل الدخول.');
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
            <div className="h-16 w-16 rounded-2xl bg-gradient-to-tr from-[#3E8FBF] to-[#7EC8E3] flex items-center justify-center text-white shadow-lg shadow-[#7EC8E3]/30 mb-3">
              <Bus className="h-8 w-8" />
            </div>
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
            </div>

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
