import { Suspense, useEffect, useState } from 'react';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { PersistQueryClientProvider } from '@tanstack/react-query-persist-client';
import { SkeletonShell } from './components/Skeleton';
import { supabase } from './lib/supabase';
import { clearCache, persistOptions, queryClient } from './lib/query';
import { loadAdminProfile } from './lib/adminProfile';
import { AdminProfile, AdminScopeProvider } from './lib/adminScope';
import { LoginPage, PlatformArea, ResetPasswordPage, Workspace } from './lib/routes';

/** The code of the area this admin lands in, fetched while the session is still being checked. */
const preloadHome = (admin: AdminProfile | null) => {
  if (!admin) LoginPage.preload();
  else if (admin.role === 'super_admin' && !window.location.pathname.startsWith('/c/')) PlatformArea.preload();
  else Workspace.preload();
};

function App() {
  const [admin, setAdmin] = useState<AdminProfile | null>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [recoveryMode, setRecoveryMode] = useState(() => /type=(recovery|invite)/.test(window.location.hash));

  // Restore only a real Supabase session whose user is listed as an admin.
  useEffect(() => {
    let mounted = true;
    // Every auth change bumps the generation. A profile lookup that resolves after
    // a newer change (e.g. sign-out) is discarded, otherwise the dashboard would
    // render without a session and every RLS query would silently return [].
    let generation = 0;

    // The check that is under way, so the same user announced twice at once (the
    // stored session and the library's own first event on a reload) is checked once.
    let checking: string | null = null;
    // Whose data the cache holds. Another account taking over this tab (a sign-in in
    // another tab replaces the shared session) starts from an empty cache: nothing the
    // previous account loaded stays in memory or is written to this tab's storage.
    let cachedFor: string | null = null;

    const applySession = async (userId: string | null) => {
      if (userId && checking === userId) return;
      const current = ++generation;
      checking = userId;
      if (!userId) {
        cachedFor = null;
        clearCache();
        preloadHome(null);
        if (mounted) { setAdmin(null); setAuthLoading(false); }
        return;
      }
      if (cachedFor && cachedFor !== userId) clearCache();
      cachedFor = userId;
      // One request: the admin row with its company (which lands in the workspace's cache).
      const profile = await loadAdminProfile(userId).catch(() => null);
      if (current === generation) checking = null;
      if (!mounted || current !== generation) return;
      preloadHome(profile);
      const { data: { session } } = await supabase.auth.getSession();
      if (!mounted || current !== generation) return;
      if (profile && session?.user.id === userId) {
        // The same admin re-checked (the library re-announces the session when the tab
        // regains focus) keeps the same object, so nothing re-renders for it.
        setAdmin((known) => (known && sameAdmin(known, profile) ? known : profile));
      } else {
        clearCache();
        setAdmin(null);
        if (session) await supabase.auth.signOut();
      }
      // Only the check that is still the latest decides what to show. On a page
      // reload two checks start almost together (the stored session and the
      // library's own first event); the first is discarded above, and ending
      // the wait there would show the sign-in page for a moment.
      if (mounted) setAuthLoading(false);
    };

    const restore = async () => {
      if (/type=(recovery|invite)/.test(window.location.hash)) setRecoveryMode(true);
      const { data: { session } } = await supabase.auth.getSession();
      await applySession(session?.user.id ?? null);
    };
    void restore();
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'PASSWORD_RECOVERY') setRecoveryMode(true);
      if (event === 'TOKEN_REFRESHED') return;
      // Supabase calls must not run inside this callback (auth lock), so defer.
      setTimeout(() => { void applySession(session?.user.id ?? null); }, 0);
    });
    // The session is shared by every tab of this browser: signing in with another
    // account in one tab replaces it everywhere. Re-check when it changes so a tab
    // never keeps acting with an account that is no longer the signed-in one.
    const onStorage = (event: StorageEvent) => {
      if (!event.key || !/^sb-.*-auth-token$/.test(event.key)) return;
      void supabase.auth.getSession().then(({ data: { session } }) => applySession(session?.user.id ?? null));
    };
    window.addEventListener('storage', onStorage);
    return () => { mounted = false; subscription.unsubscribe(); window.removeEventListener('storage', onStorage); };
  }, []);

  const handleLogout = async () => {
    await supabase.auth.signOut();
    clearCache();
    setAdmin(null);
  };

  // While the session is checked, the frame of the dashboard, not a blank page.
  if (authLoading) return <SkeletonShell />;
  if (recoveryMode) return <Suspense fallback={<SkeletonShell />}><ResetPasswordPage onComplete={() => setRecoveryMode(false)} /></Suspense>;
  if (!admin) {
    return <Suspense fallback={<SkeletonShell />}><LoginPage onLogin={setAdmin} /></Suspense>;
  }

  // A platform admin starts in the platform area; a company admin lives in their
  // own workspace and has no other address to go to.
  const home = admin.role === 'super_admin' ? '/platform' : `/c/${admin.company_id}`;
  return (
    <PersistQueryClientProvider client={queryClient} persistOptions={persistOptions(admin.id)}>
    <AdminScopeProvider admin={admin}>
      <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        {/* The area's code is its own file (a company admin never downloads the platform's pages). */}
        <Suspense fallback={<SkeletonShell />}>
        <Routes>
          {admin.role === 'super_admin' && (
            <Route path="/platform/*" element={<PlatformArea onLogout={handleLogout} />} />
          )}
          <Route path="/c/:companyId/*" element={<Workspace admin={admin} onLogout={handleLogout} />} />
          <Route path="*" element={<Navigate to={home} replace />} />
        </Routes>
        </Suspense>
      </BrowserRouter>
    </AdminScopeProvider>
    </PersistQueryClientProvider>
  );
}

const sameAdmin = (a: AdminProfile, b: AdminProfile) =>
  a.id === b.id && a.email === b.email && a.full_name === b.full_name && a.role === b.role
  && a.company_id === b.company_id && a.companyName === b.companyName;

export default App;
